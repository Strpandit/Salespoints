module Api
  class ProductsController < ApplicationController
    PUBLIC_ACTIONS = %i[index active_products active_product_facets show similar_product].freeze

    skip_before_action :authenticate_request!, only: PUBLIC_ACTIONS
    before_action :require_admin, except: PUBLIC_ACTIONS
    before_action :check_permission, except: PUBLIC_ACTIONS

    # Displayed retail price = cheapest live variant, falling back to the product-level price.
    STOREFRONT_PRICE_SQL = <<~SQL.squish.freeze
      COALESCE((SELECT MIN(pv.selling_price) FROM product_variants pv
                WHERE pv.product_id = products.id AND pv.deleted_at IS NULL AND pv.is_active = TRUE),
               products.selling_price)
    SQL
    RATING_SQL = "(SELECT COALESCE(AVG(r.rating), 0) FROM reviews r WHERE r.product_id = products.id)".freeze
    REVIEW_COUNT_SQL = "(SELECT COUNT(*) FROM reviews r WHERE r.product_id = products.id)".freeze
    before_action :find_product, only: [:show, :update, :destroy]

    def index
      products = Product.includes(:category, :brand, :product_variants)

      if params[:category_id].present? && params[:category_id] != "all"
        products = products.where(category_id: params[:category_id])
      end

      if params[:brand_id].present? && params[:brand_id] != "all"
        products = products.where(brand_id: params[:brand_id])
      end

      if params[:is_active].present? && params[:is_active] != "all"
        is_act = ActiveModel::Type::Boolean.new.cast(params[:is_active])
        products = products.where(is_active: is_act)
      end

      if params[:search].present?
        q = "%#{params[:search].strip}%"
        products = products.joins("LEFT JOIN product_variants ON product_variants.product_id = products.id")
                           .where("products.name ILIKE :q OR products.hsn_code ILIKE :q OR product_variants.variant_sku ILIKE :q", q: q)
                           .distinct
      end

      case params[:sort_by]
      when "oldest"
        products = products.order("products.created_at ASC")
      when "name_asc"
        products = products.order("products.name ASC")
      when "name_desc"
        products = products.order("products.name DESC")
      else
        products = products.order("products.created_at DESC")
      end

      products = products.page(params[:page]).per(params[:per_page] || 20)
      render json: serialize_resource(products, ProductSerializer, base_url: request.base_url).merge(
        meta: {
          current_page: products.current_page,
          next_page: products.next_page,
          prev_page: products.prev_page,
          total_pages: products.total_pages,
          total_count: products.total_count
        },
        message: "Products fetched successfully"
      ), status: :ok
    end

    def active_products
      products = Product.active.includes(:category, :brand, :product_variants)
      products = apply_storefront_filters(products)
      products = apply_active_product_sort(products, params[:sort])
      per_page = (params[:per_page] || 20).to_i.clamp(1, 100)
      products = products.page(params[:page]).per(per_page)
      ratings = rating_stats_for(products.map(&:id))

      render json: serialize_resource(products, ProductSerializer, base_url: request.base_url, ratings: ratings).merge(
        meta: {
          current_page: products.current_page,
          next_page: products.next_page,
          prev_page: products.prev_page,
          total_pages: products.total_pages,
          total_count: products.total_count
        },
        message: "Products fetched successfully"
      ), status: :ok
    end

    # GET /api/active_products/facets - filter options (brands, specs, price range) across the
    # whole matching catalog, not just one page. Brand/spec/price/rating selections are ignored
    # on purpose, so picking one brand doesn't hide the other brands from the list.
    def active_product_facets
      scope = apply_storefront_filters(Product.active, skip: %i[brands specs min_price max_price min_rating])
      ids = scope.pluck(:id)

      brands = Brand.joins(:products).where(products: { id: ids })
                    .group("brands.name").order("brands.name").count
      specs = ProductSpecification.where(product_id: ids)
                                  .where.not(key: [nil, ""]).where.not(value: [nil, ""])
                                  .distinct.pluck(:key, :value)
                                  .group_by { |k, _| k.strip }
                                  .transform_values { |pairs| pairs.map { |_, v| v.strip }.uniq.sort }
                                  .select { |_, values| values.size.between?(2, 12) && values.all? { |v| v.length <= 25 } }
      prices = ids.any? ? Product.where(id: ids).pluck(Arel.sql(STOREFRONT_PRICE_SQL)).compact.map(&:to_f) : []

      render json: {
        data: {
          brands: brands.map { |name, count| { name: name, count: count } },
          specs: specs.sort.to_h,
          price_range: { min: prices.min, max: prices.max },
          total_count: ids.size
        }
      }, status: :ok
    end

    def show
      render json: serialize_resource(@product, ProductSerializer, base_url: request.base_url).merge(
        message: "Product fetched successfully"
      ), status: :ok
    end

    def similar_product
      products = Product.active.where(category_id: params[:category_id])
                        .where.not(id: params[:product_id])
                        .limit(4)
    
      if products.present?
        render json: serialize_resource(products, ProductSerializer, base_url: request.base_url).merge(
          message: "Similar products fetched successfully"
        ), status: :ok
      else
        render json: { errors: "No similar products found" }, status: :not_found
      end
    end

    def create
      product = Product.new(normalized_product_params)

      if product.save
        notify_admins_entity_created(product)
        render json: serialize_resource(product, ProductSerializer, base_url: request.base_url).merge(
          message: "Product created successfully"
        ), status: :created
      else
        render json: { error: product.errors.full_messages }, status: :unprocessable_entity
      end
    end

  def update
    purge_blob_ids = extract_purge_blob_ids
    variant_purge_map = extract_variant_purge_blob_ids
    color_purge_map = extract_color_purge_blob_ids

    old_attributes = @product.attributes.slice(
      "name", "slug", "model", "sku", "description", "short_description",
      "material", "hsn_code", "tax_rate", "is_active", "is_featured", "is_new",
      "brand_id", "category_id", "features", "care_instructions"
    )
    old_brand_name = @product.brand&.name
    old_category_name = @product.category&.name
    old_variants = @product.product_variants.map { |v| [v.id, { sku: v.variant_sku, price: v.price, selling_price: v.selling_price, dealer_price: v.dealer_price, is_active: v.is_active }] }.to_h
    old_specs = @product.product_specifications.map { |s| [s.key, s.value] }.to_h
    old_media_count = @product.media.attached? ? @product.media_attachments.count : 0

    if @product.update(normalized_product_params)
      purge_media_blobs!(@product, purge_blob_ids)
      apply_variant_media_purges!(variant_purge_map)
      apply_color_media_purges!(color_purge_map)

      changes = compute_product_changes(
        old_attributes, old_brand_name, old_category_name,
        old_variants, old_specs, old_media_count
      )
      notify_admins_entity_updated(@product, changes)
        render json: serialize_resource(@product, ProductSerializer, base_url: request.base_url).merge(
          message: "Product updated successfully"
        ), status: :ok
      else
        render json: { error: @product.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def destroy
      @product.update(deleted_at: Time.current, is_active: false, is_featured: false, is_new: false)
      @product.product_variants.update_all(is_active: false)
      notify_admins_entity_deleted(@product)
      render json: { message: "Product deleted successfully" }, status: :ok
    end

    private

    VARIANT_FIELD_KEYS = %i[
      variant_sku
      price
      selling_price
      dealer_price
      dealer_selling_price
      discount_percentage
      is_active
      variant_attributes
    ].freeze

    def product_params
      params.require(:product).permit(
        :name, :slug, :desc, :material, :brand_id, :category_id,
        :is_featured, :is_new, :is_active, :tax_rate, :hsn_code,
        :price, :selling_price, :dealer_price, :dealer_selling_price, :discount_percentage,
        :primary_media_blob_id, :primary_new_media_index,
        :purge_media_blob_ids, { purge_media_blob_ids: [] },
        :features, :care_instructions,
        media: [],
        features: [], care_instructions: [],
        product_specifications_attributes: [:id, :key, :value, :_destroy],
        product_variant_colors_attributes: [
          :id, :color_name, :color_hex, :primary_media_blob_id, :primary_new_media_index, :_destroy,
          :purge_media_blob_ids, { purge_media_blob_ids: [] },
          { media: [] }
        ],
        product_variants_attributes: [
          :id, :variant_sku, :price, :selling_price, :dealer_price, :hsn_code,
          :dealer_selling_price, :discount_percentage, :is_active, :_destroy,
          { variant_attributes: [:key, :value] }
        ]
      )
    end

    def normalized_product_params
      attrs = product_params.to_h.deep_dup

      if attrs.key?("features")
        attrs["features"] = normalize_text_list(attrs["features"])
      end

      if attrs.key?("care_instructions")
        attrs["care_instructions"] = normalize_text_list(attrs["care_instructions"])
      end

      variant_attrs = attrs["product_variants_attributes"]
      return attrs if variant_attrs.present?
      return attrs if @product&.product_variants&.exists?

      fallback_variant = build_fallback_variant_attributes(attrs)
      return attrs if fallback_variant.blank?

      attrs["product_variants_attributes"] = [fallback_variant]
      attrs
    end

    def normalize_text_list(val)
      return [] if val.blank?
      Array(val).flat_map do |item|
        item.is_a?(String) ? item.split(/\r?\n/) : item
      end.map(&:to_s).map(&:strip).reject(&:blank?)
    end

    def build_fallback_variant_attributes(attrs)
      variant_attrs = {}
      VARIANT_FIELD_KEYS.each do |key|
        value = attrs.delete(key.to_s)
        variant_attrs[key.to_s] = value if value.present?
      end

      variant_attrs["variant_sku"] ||= generated_default_variant_sku(attrs["name"])
      return if variant_attrs.except("variant_sku", "is_active").values.all?(&:blank?)

      variant_attrs["is_active"] = true if variant_attrs["is_active"].nil?
      variant_attrs
    end

    def generated_default_variant_sku(product_name)
      name_clean = product_name.to_s.parameterize.upcase
      return if name_clean.blank?

      "#{name_clean}-DEFAULT"
    end

    # All storefront filters are opt-in: a missing param leaves the list unchanged, so older
    # web/app builds that never sent them behave exactly as before.
    def apply_storefront_filters(scope, skip: [])
      category_ids = params[:category_id].to_s.split(",").map(&:strip).reject(&:blank?)
      scope = scope.where(category_id: category_ids) if category_ids.any?

      if params[:category_slug].present? && category_ids.empty?
        scope = scope.where(category_id: Category.where(slug: params[:category_slug]).select(:id))
      end

      if params[:search].present?
        q = "%#{ActiveRecord::Base.sanitize_sql_like(params[:search].strip)}%"
        scope = scope.where(
          "products.name ILIKE :q OR products.brand_id IN (SELECT id FROM brands WHERE name ILIKE :q) " \
          "OR products.category_id IN (SELECT id FROM categories WHERE name ILIKE :q) " \
          "OR products.id IN (SELECT product_id FROM product_variants WHERE variant_sku ILIKE :q AND deleted_at IS NULL)",
          q: q
        )
      end

      unless skip.include?(:brands)
        brand_names = params[:brands].to_s.split(",").map { |b| b.strip.downcase }.reject(&:blank?)
        scope = scope.where("products.brand_id IN (SELECT id FROM brands WHERE LOWER(name) IN (?))", brand_names) if brand_names.any?
      end

      if !skip.include?(:min_price) && params[:min_price].present?
        scope = scope.where("#{STOREFRONT_PRICE_SQL} >= ?", params[:min_price].to_f)
      end
      if !skip.include?(:max_price) && params[:max_price].present?
        scope = scope.where("#{STOREFRONT_PRICE_SQL} <= ?", params[:max_price].to_f)
      end
      if !skip.include?(:min_rating) && params[:min_rating].to_f.positive?
        scope = scope.where("#{RATING_SQL} >= ?", params[:min_rating].to_f)
      end

      scope = apply_spec_filters(scope) unless skip.include?(:specs)
      scope
    end

    # specs = JSON {"RAM": ["8 GB", "12 GB"], "Storage": ["256 GB"]} -> must match every key.
    def apply_spec_filters(scope)
      raw = params[:specs]
      return scope if raw.blank?

      specs =
        if raw.is_a?(String)
          JSON.parse(raw) rescue {}
        elsif raw.respond_to?(:to_unsafe_h)
          raw.to_unsafe_h
        else
          {}
        end
      return scope unless specs.is_a?(Hash)

      specs.each do |key, values|
        values = Array(values).map { |v| v.to_s.strip }.reject(&:blank?)
        next if key.to_s.strip.blank? || values.empty?

        scope = scope.where(
          "EXISTS (SELECT 1 FROM product_specifications ps WHERE ps.product_id = products.id " \
          "AND LOWER(TRIM(ps.key)) = LOWER(?) AND TRIM(ps.value) IN (?))",
          key.to_s.strip, values
        )
      end
      scope
    end

    # { product_id => { average: 4.3, count: 12 } } in one query, so listings don't N+1.
    def rating_stats_for(product_ids)
      return {} if product_ids.blank?

      Review.where(product_id: product_ids).group(:product_id)
            .pluck(:product_id, Arel.sql("AVG(rating)"), Arel.sql("COUNT(*)"))
            .to_h { |id, avg, count| [id, { average: avg.to_f.round(1), count: count.to_i }] }
    end

    def apply_active_product_sort(scope, sort)
      case sort
      when "price_asc"
        scope.left_joins(:product_variants)
             .group("products.id")
             .order(Arel.sql("MIN(product_variants.selling_price) ASC NULLS LAST"))
      when "price_desc"
        scope.left_joins(:product_variants)
             .group("products.id")
             .order(Arel.sql("MIN(product_variants.selling_price) DESC NULLS LAST"))
      when "a_to_z"
        scope.order(Arel.sql("LOWER(products.name) ASC"))
      when "z_to_a"
        scope.order(Arel.sql("LOWER(products.name) DESC"))
      when "popularity"
        scope.order(Arel.sql("#{REVIEW_COUNT_SQL} DESC, #{RATING_SQL} DESC, products.created_at DESC"))
      else
        scope.order(created_at: :desc)
      end
    end

    def find_product
      @product = Product.find_by(id: params[:id]) || Product.find_by(slug: params[:id])
      render json: { error: "Product not found" }, status: :not_found unless @product
    end

    def check_permission
      unless current_admin.can_access?(:products)
        render json: { error: "You do not have permission to manage products"}, status: :forbidden
      end
    end

    def require_admin
      render json: { error: "Admin only" }, status: :unauthorized unless current_user_type == "AdminUser"
    end

    def current_admin
      current_user
    end

    def extract_purge_blob_ids
      blob_ids = []

      product_blob_ids = params.dig(:product, :purge_media_blob_ids)
      if product_blob_ids.present?
        blob_ids.concat(Array(product_blob_ids))
      end

      variants = params.dig(:product, :product_variants_attributes)
      if variants.present?
        variants.each do |_index, attrs|
          if attrs.is_a?(ActionController::Parameters)
            attrs = attrs.to_unsafe_h
          end

          variant_blob_ids = attrs["purge_media_blob_ids"] || attrs[:purge_media_blob_ids]
          if variant_blob_ids.present?
            blob_ids.concat(Array(variant_blob_ids))
          end
        end
      end

      blob_ids.map(&:to_i).reject(&:zero?).uniq
    end

    def extract_variant_purge_blob_ids
      variants = params.dig(:product, :product_variants_attributes)
      return {} if variants.blank?

      variants = variants.to_unsafe_h if variants.is_a?(ActionController::Parameters)

      map = {}

      variants.each do |_index, attrs|
        attrs = attrs.to_unsafe_h if attrs.is_a?(ActionController::Parameters)

        variant_id = attrs["id"] || attrs[:id]
        next if variant_id.blank?
        blob_ids = []

        if attrs["purge_media_blob_ids"].present?
          blob_ids.concat(Array(attrs["purge_media_blob_ids"]))
        end

        if attrs[:purge_media_blob_ids].present?
          blob_ids.concat(Array(attrs[:purge_media_blob_ids]))
        end

        blob_ids = blob_ids.map(&:to_i).reject(&:zero?).uniq

        map[variant_id.to_i] = blob_ids if blob_ids.any?
      end

      map
    end

    def purge_media_blobs!(record, blob_ids)
      return if blob_ids.blank?

      record.media_attachments.each do |attachment|
        if blob_ids.include?(attachment.blob_id)
          attachment.purge
        end
      end

      if blob_ids.include?(record.primary_media_blob_id)
        remaining = record.media_attachments.first
        record.update_column(:primary_media_blob_id, remaining&.blob_id)
      end
    end

    def apply_variant_media_purges!(variant_purge_map)
      variant_purge_map.each do |variant_id, blob_ids|
        variant = @product.product_variants.find_by(id: variant_id)
        purge_media_blobs!(variant, blob_ids) if variant
      end
    end

    def extract_color_purge_blob_ids
      colors = params.dig(:product, :product_variant_colors_attributes)
      return {} if colors.blank?

      colors = colors.to_unsafe_h if colors.is_a?(ActionController::Parameters)

      map = {}
      colors.each do |_index, attrs|
        attrs = attrs.to_unsafe_h if attrs.is_a?(ActionController::Parameters)
        color_id = attrs["id"] || attrs[:id]
        next if color_id.blank?
        blob_ids = []

        if attrs["purge_media_blob_ids"].present?
          blob_ids.concat(Array(attrs["purge_media_blob_ids"]))
        end
        if attrs[:purge_media_blob_ids].present?
          blob_ids.concat(Array(attrs[:purge_media_blob_ids]))
        end

        blob_ids = blob_ids.map(&:to_i).reject(&:zero?).uniq
        map[color_id.to_i] = blob_ids if blob_ids.any?
      end
      map
    end

    def apply_color_media_purges!(color_purge_map)
      color_purge_map.each do |color_id, blob_ids|
        color = @product.product_variant_colors.find_by(id: color_id)
        purge_media_blobs!(color, blob_ids) if color
      end
    end

    ### notification helpers
    def get_admin_emails
      emails = AdminUser.where(status: "active", is_super_admin: true).pluck(:email)
      emails << current_admin.email if respond_to?(:current_admin) && current_admin&.email.present?
      emails.compact.map(&:strip).reject(&:blank?).uniq
    end

    def compute_product_changes(old_attrs, old_brand_name, old_category_name, old_variants, old_specs, old_media_count)
      changes = {}

      # 1. Main product direct attributes
      current_attrs = @product.reload.attributes
      old_attrs.each do |key, old_val|
        new_val = current_attrs[key]
        next if old_val == new_val

        case key
        when "brand_id"
          new_brand_name = @product.brand&.name || Brand.find_by(id: new_val)&.name
          changes["brand"] = { from: old_brand_name.presence || "—", to: new_brand_name.presence || "—" }
        when "category_id"
          new_cat_name = @product.category&.name || Category.find_by(id: new_val)&.name
          changes["category"] = { from: old_category_name.presence || "—", to: new_cat_name.presence || "—" }
        else
          changes[key] = { from: old_val, to: new_val }
        end
      end

      # 2. Variants / Prices changes
      @product.product_variants.reload.each do |v|
        old_v = old_variants[v.id]
        if old_v.present?
          label_suffix = v.variant_sku.present? ? " (#{v.variant_sku})" : ""
          if old_v[:price] != v.price
            changes["price#{label_suffix}"] = { from: old_v[:price] ? "₹#{old_v[:price]}" : "—", to: v.price ? "₹#{v.price}" : "—" }
          end
          if old_v[:selling_price] != v.selling_price
            changes["selling_price#{label_suffix}"] = { from: old_v[:selling_price] ? "₹#{old_v[:selling_price]}" : "—", to: v.selling_price ? "₹#{v.selling_price}" : "—" }
          end
          if old_v[:dealer_price] != v.dealer_price
            changes["dealer_price#{label_suffix}"] = { from: old_v[:dealer_price] ? "₹#{old_v[:dealer_price]}" : "—", to: v.dealer_price ? "₹#{v.dealer_price}" : "—" }
          end
          if old_v[:is_active] != v.is_active
            changes["status#{label_suffix}"] = { from: old_v[:is_active] ? "Active" : "Inactive", to: v.is_active ? "Active" : "Inactive" }
          end
        else
          changes["new_variant"] = { from: "—", to: "#{v.variant_sku.presence || 'Default'} (₹#{v.selling_price || v.price})" }
        end
      end

      old_variants.each do |vid, vdata|
        unless @product.product_variants.exists?(id: vid)
          changes["removed_variant"] = { from: vdata[:sku], to: "—" }
        end
      end

      # 3. Product Specifications
      new_specs = @product.product_specifications.reload.map { |s| [s.key, s.value] }.to_h
      (old_specs.keys | new_specs.keys).each do |k|
        if old_specs[k] != new_specs[k]
          changes["specification_#{k}"] = { from: old_specs[k] || "—", to: new_specs[k] || "Removed" }
        end
      end

      # 4. Media Files
      new_media_count = @product.media.attached? ? @product.media_attachments.count : 0
      if new_media_count != old_media_count
        changes["media_files"] = { from: "#{old_media_count} files", to: "#{new_media_count} files" }
      end

      # Fallback to direct saved_changes if custom diff was empty
      if changes.empty?
        @product.saved_changes.except("updated_at", "created_at", "primary_media_blob_id").each do |k, (before, after)|
          changes[k] = { from: before, to: after }
        end
      end

      changes
    end

    def notify_admins_entity_created(product)
      details = product.attributes.except("id", "created_at", "updated_at", "primary_media_blob_id")
      details["brand"] = product.brand&.name || details["brand_id"]
      details.delete("brand_id")
      details["category"] = product.category&.name || details["category_id"]
      details.delete("category_id")
      get_admin_emails.each do |email|
        AdminNotificationMailer.entity_created(email, "Product", product.name, current_admin, details).deliver_later
      end
    end

    def notify_admins_entity_updated(product, custom_changes = nil)
      changes = custom_changes || product.saved_changes.except("updated_at", "created_at").transform_values { |v| { from: v[0], to: v[1] } }
      get_admin_emails.each do |email|
        AdminNotificationMailer.entity_updated(email, "Product", product.name, current_admin, changes).deliver_later
      end
    end

    def notify_admins_entity_deleted(product)
      details = product.attributes.except("id", "created_at", "updated_at", "primary_media_blob_id")
      details["brand"] = product.brand&.name || details["brand_id"]
      details.delete("brand_id")
      details["category"] = product.category&.name || details["category_id"]
      details.delete("category_id")
      get_admin_emails.each do |email|
        AdminNotificationMailer.entity_deleted(email, "Product", product.name, current_admin, details).deliver_later
      end
    end
  end
end
