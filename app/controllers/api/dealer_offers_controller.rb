module Api
  class DealerOffersController < ApplicationController
    skip_before_action :authenticate_request!, only: [ :index, :show, :check_pincode, :scheme_categories ]
    before_action :optional_authenticate, only: [ :index, :show, :check_pincode ]
    before_action :require_admin!, only: [ :pending, :approve, :reject ]
    before_action :set_offer, only: [ :show, :update, :destroy, :toggle_active, :approve, :reject, :check_pincode, :buy ]

    # GET /api/dealer_offers
    def index
      offers = base_includes

      offers =
        if current_admin.present?
          admin_index_scope(offers)
        elsif current_dealer.present?
          offers.where(dealer_id: current_dealer.id)
        else
          public_index_scope(offers)
        end

      offers = apply_common_filters(offers)
      offers = apply_sort(offers)

      paginated = offers.page(params[:page]).per(params[:per_page] || 20)

      render json: {
        data: paginated.map { |offer| offer_payload(offer) },
        meta: pagination_meta(paginated)
      }, status: :ok
    end

    # GET /api/dealer_offers/:id
    def show
      unless @offer.live? || owner?(@offer) || current_admin.present?
        return render json: { error: "Offer is not available" }, status: :forbidden
      end

      render json: { data: offer_payload(@offer) }, status: :ok
    end

    # POST /api/dealer_offers
    def create
      return render json: { error: "Only dealers can create offers" }, status: :forbidden unless current_dealer

      dealer_product = current_dealer.dealer_products.for_b2c.find_by(id: params.dig(:dealer_offer, :dealer_product_id))
      return render json: { error: "Select one of your B2C products for this offer" }, status: :unprocessable_entity unless dealer_product

      if params.dig(:dealer_offer, :pincodes).blank?
        return render json: { error: "At least one delivery pincode is required" }, status: :unprocessable_entity
      end

      offer = current_dealer.dealer_offers.new(offer_params)
      assign_catalog_fields(offer, dealer_product)
      offer.approve_status = "pending"

      if offer.save
        render json: { data: offer_payload(offer), message: "Offer submitted for admin review" }, status: :created
      else
        render json: { error: offer.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # PATCH/PUT /api/dealer_offers/:id
    def update
      return admin_update_offer if current_admin.present?
      return render json: { error: "Only dealers can edit offers" }, status: :forbidden unless current_dealer
      return render json: { error: "You can edit only your own offer" }, status: :forbidden unless owner?(@offer)

      if params[:dealer_offer].key?(:dealer_product_id) && params[:dealer_offer][:dealer_product_id].present?
        dealer_product = current_dealer.dealer_products.for_b2c.find_by(id: params[:dealer_offer][:dealer_product_id])
        return render json: { error: "Invalid product selection" }, status: :unprocessable_entity unless dealer_product
        assign_catalog_fields(@offer, dealer_product)
      end

      if params[:dealer_offer].key?(:pincodes) && params[:dealer_offer][:pincodes].blank?
        return render json: { error: "At least one delivery pincode is required" }, status: :unprocessable_entity
      end

      @offer.assign_attributes(offer_params)

      if @offer.changed?
        @offer.approve_status = "pending"
        @offer.reviewed_at = nil
        @offer.reviewed_by_admin = nil
        @offer.rejection_reason = nil
      end

      if @offer.save
        render json: { data: offer_payload(@offer), message: "Offer updated and sent for review" }, status: :ok
      else
        render json: { error: @offer.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # DELETE /api/dealer_offers/:id
    def destroy
      return render json: { error: "Only dealers can delete offers" }, status: :forbidden unless current_dealer
      return render json: { error: "You can delete only your own offer" }, status: :forbidden unless owner?(@offer)

      @offer.destroy
      render json: { message: "Offer deleted" }, status: :ok
    end

    # PATCH /api/dealer_offers/:id/toggle_active
    def toggle_active
      unless owner?(@offer) || current_admin.present?
        return render json: { error: "Not authorized" }, status: :forbidden
      end

      unless @offer.approve_status == "approved"
        return render json: { error: "Only approved offers can be toggled" }, status: :unprocessable_entity
      end

      @offer.update!(is_active: !@offer.is_active)
      render json: { data: offer_payload(@offer), message: "Offer visibility updated" }, status: :ok
    end

    # GET /api/dealer_offers/pending  (admin)
    def pending
      offers = current_admin.accessible_dealer_offers(base_includes)
      offers = offers.where(approve_status: params[:status]) if params[:status].present? && params[:status] != "all"
      offers = apply_common_filters(offers)
      offers = apply_sort(offers)

      paginated = offers.page(params[:page]).per(params[:per_page] || 15)

      render json: {
        data: paginated.map { |offer| offer_payload(offer) },
        meta: pagination_meta(paginated)
      }, status: :ok
    end

    # PATCH /api/dealer_offers/:id/approve  (admin)
    def approve
      return render json: { error: "Access denied for this offer" }, status: :forbidden unless admin_can_access?(@offer)

      @offer.update!(
        approve_status: "approved",
        rejection_reason: nil,
        reviewed_at: Time.current,
        reviewed_by_admin: current_admin
      )
      render json: { data: offer_payload(@offer), message: "Offer approved" }, status: :ok
    end

    # PATCH /api/dealer_offers/:id/reject  (admin)
    def reject
      return render json: { error: "Access denied for this offer" }, status: :forbidden unless admin_can_access?(@offer)

      reason = params[:rejection_reason].presence || params[:reason].presence
      return render json: { error: "Rejection reason is required" }, status: :unprocessable_entity if reason.blank?

      @offer.update!(
        approve_status: "rejected",
        rejection_reason: reason,
        reviewed_at: Time.current,
        reviewed_by_admin: current_admin
      )
      render json: { data: offer_payload(@offer), message: "Offer rejected" }, status: :ok
    end

    # GET /api/dealer_offers/:id/check_pincode?pincode=XXXXXX
    def check_pincode
      pincode = params[:pincode].to_s.strip
      return render json: { error: "Pincode is required" }, status: :unprocessable_entity if pincode.blank?

      deliverable = @offer.live? && @offer.pincodes.include?(pincode)

      render json: {
        deliverable: deliverable,
        remaining_quantity: @offer.remaining_quantity,
        message: deliverable ? "This offer is available for your pincode" : "This offer is not available for your pincode"
      }, status: :ok
    end

    # POST /api/dealer_offers/:id/buy   (account users only)
    def buy
      return render json: { error: "Please login with your customer account to buy offers" }, status: :forbidden unless current_account

      shipping_address = params[:shipping_address].presence || account_default_address
      billing_address = params[:billing_address].presence || shipping_address
      pincode = params[:pincode].presence || shipping_address["postal_code"] || shipping_address[:postal_code]

      return render json: { error: "Pincode is required for delivery" }, status: :unprocessable_entity if pincode.blank?

      result = OfferMartBuyNowService.new(
        buyer: current_account,
        dealer_offer: @offer,
        quantity: params[:quantity] || 1,
        payment_method: params[:payment_method].to_s.presence || "cod",
        shipping_address: shipping_address,
        billing_address: billing_address,
        pincode: pincode
      ).call

      render json: {
        data: serialize_data(result.order, OrderSerializer),
        order: serialize_data(result.order, OrderSerializer),
        payment: result.payment_data,
        message: "Order placed successfully."
      }, status: :created
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # GET /api/dealer_offers/scheme_categories
    def scheme_categories
      render json: {
        scheme_categories: DealerOffer::SCHEME_CATEGORIES,
        product_conditions: DealerOffer::PRODUCT_CONDITIONS
      }, status: :ok
    end

    private

    def optional_authenticate
      token = request.headers["Authorization"]&.split(" ")&.last
      return if token.blank?

      payload = JsonWebToken.decode(token)
      return if payload.blank?

      @current_user_type = payload[:user_type]
      @current_user = find_user(payload)
    rescue StandardError
      nil
    end

    def require_admin!
      return if current_admin.present?

      render json: { error: "Admin only" }, status: :forbidden
    end

    def set_offer
      @offer = DealerOffer.includes(:media_attachments, :dealer, :product, :product_variant).find_by(id: params[:id])
      render json: { error: "Offer not found" }, status: :not_found unless @offer
    end

    def base_includes
      DealerOffer.includes(:media_attachments, dealer: :dealer_profile)
    end

    def owner?(offer)
      current_dealer.present? && offer.dealer_id == current_dealer.id
    end

    def admin_can_access?(offer)
      return true if current_admin.super_admin?

      current_admin.accessible_dealer_offers(DealerOffer.where(id: offer.id)).exists?
    end

    def admin_index_scope(offers)
      unless current_admin.can_access?(:dealer_offers, :read)
        return offers.none
      end

      scope = current_admin.accessible_dealer_offers(offers)
      scope = scope.where(dealer_id: params[:dealer_id]) if params[:dealer_id].present? && params[:dealer_id] != "all"
      scope = scope.where(approve_status: params[:approve_status]) if params[:approve_status].present? && params[:approve_status] != "all"
      scope
    end

    def public_index_scope(offers)
      scope = offers.visible_to_marketplace
      scope = scope.by_pincode(params[:pincode]) if params[:pincode].present?
      scope
    end

    def apply_common_filters(scope)
      if params[:scheme_category].present? && params[:scheme_category] != "all"
        scope = scope.where(scheme_category: params[:scheme_category])
      end

      if params[:product_condition].present? && params[:product_condition] != "all"
        scope = scope.where(product_condition: params[:product_condition])
      end

      if params[:brand].present?
        scope = scope.where("dealer_offers.brand_name ILIKE ?", "%#{params[:brand].strip}%")
      end

      scope = scope.where("dealer_offers.offer_price >= ?", params[:min_price].to_f) if params[:min_price].present?
      scope = scope.where("dealer_offers.offer_price <= ?", params[:max_price].to_f) if params[:max_price].present?

      if params[:search].present?
        q = "%#{params[:search].strip}%"
        scope = scope.where(
          "dealer_offers.offer_name ILIKE :q OR dealer_offers.brand_name ILIKE :q OR dealer_offers.device_model ILIKE :q OR dealer_offers.seller_code ILIKE :q",
          q: q
        )
      end

      scope
    end

    def apply_sort(scope)
      case params[:sort_by]
      when "price_asc"
        scope.order("dealer_offers.offer_price ASC")
      when "price_desc"
        scope.order("dealer_offers.offer_price DESC")
      when "ending_soon"
        scope.order(Arel.sql("dealer_offers.offer_ends_at ASC NULLS LAST"))
      when "discount_desc"
        scope.order(Arel.sql("((dealer_offers.mrp - dealer_offers.offer_price) / NULLIF(dealer_offers.mrp, 0)) DESC"))
      when "oldest"
        scope.order("dealer_offers.created_at ASC")
      else
        scope.order("dealer_offers.created_at DESC")
      end
    end

    def pagination_meta(records)
      {
        current_page: records.current_page,
        next_page: records.next_page,
        prev_page: records.prev_page,
        total_pages: records.total_pages,
        total_count: records.total_count
      }
    end

    def offer_params
      params.require(:dealer_offer).permit(
        :offer_name, :scheme_category, :product_condition, :seller_code, :special_terms,
        :brand_name, :device_model, :variant_name, :ram_storage, :colour,
        :imei_required, :warranty, :included_accessories, :return_replacement,
        :mrp, :seller_price, :offer_price, :tax_rate,
        :available_quantity, :offer_starts_at, :offer_ends_at,
        media: [], pincodes: []
      )
    end

    def assign_catalog_fields(offer, dealer_product)
      product = dealer_product.product
      variant = dealer_product.product_variant

      offer.dealer_product = dealer_product
      offer.product = product
      offer.product_variant = variant
      offer.brand_name = offer.brand_name.presence || product&.brand&.name
      offer.device_model = offer.device_model.presence || product&.name
      offer.variant_name = offer.variant_name.presence || variant&.variant_sku
    end

    def admin_update_offer
      unless current_admin.can_access?(:dealer_offers, :write)
        return render json: { error: "Access denied" }, status: :forbidden
      end
      return render json: { error: "Access denied for this offer" }, status: :forbidden unless admin_can_access?(@offer)

      @offer.assign_attributes(offer_params)
      @offer.reviewed_by_admin = current_admin
      @offer.reviewed_at = Time.current

      if @offer.save
        render json: { data: offer_payload(@offer), message: "Offer updated successfully" }, status: :ok
      else
        render json: { error: @offer.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def account_default_address
      return {} unless current_account

      address = current_account.addresses.find_by(is_default: true) || current_account.addresses.order(created_at: :desc).first
      return {} if address.blank?

      {
        name: address.name,
        phone: address.phone,
        address_line1: address.address_line1,
        address_line2: address.address_line2,
        city: address.city,
        state: address.state,
        postal_code: address.postal_code,
        country: address.country
      }.stringify_keys
    end

    def offer_payload(offer)
      dealer = offer.dealer
      {
        id: offer.id,
        offer_name: offer.offer_name,
        scheme_category: offer.scheme_category,
        product_condition: offer.product_condition,
        seller_code: offer.seller_code,
        special_terms: offer.special_terms,
        brand_name: offer.brand_name,
        device_model: offer.device_model,
        variant_name: offer.variant_name,
        ram_storage: offer.ram_storage,
        colour: offer.colour,
        imei_required: offer.imei_required,
        warranty: offer.warranty,
        included_accessories: offer.included_accessories,
        return_replacement: offer.return_replacement,
        mrp: offer.mrp.to_f,
        seller_price: offer.seller_price.to_f,
        offer_price: offer.offer_price.to_f,
        tax_rate: offer.effective_tax_rate.to_f,
        discount_percentage: offer.discount_percentage,
        available_quantity: offer.available_quantity,
        sold_quantity: offer.sold_quantity,
        remaining_quantity: offer.remaining_quantity,
        offer_starts_at: offer.offer_starts_at,
        offer_ends_at: offer.offer_ends_at,
        pincodes: offer.pincodes,
        approve_status: offer.approve_status,
        rejection_reason: offer.rejection_reason,
        reviewed_at: offer.reviewed_at,
        is_active: offer.is_active,
        is_live: offer.live?,
        is_expired: offer.expired?,
        is_owner: owner?(offer),
        hsn_code: offer.effective_hsn_code,
        dealer_id: offer.dealer_id,
        dealer_product_id: offer.dealer_product_id,
        product_id: offer.product_id,
        product_variant_id: offer.product_variant_id,
        product_slug: offer.product&.slug,
        dealer: dealer && {
          id: dealer.id,
          dealer_code: dealer.dealer_code,
          full_name: dealer.full_name,
          business_name: dealer.dealer_profile&.business_name,
          store_image: dealer.dealer_profile&.store_image&.attached? ?
            dealer.dealer_profile.store_image.map { |file| attachment_payload(file) } : []
        },
        dealer_name: dealer_display_name(dealer),
        media: offer.media.map { |file| attachment_payload(file) },
        created_at: offer.created_at,
        updated_at: offer.updated_at
      }
    end

    def attachment_payload(file)
      {
        id: file.id,
        url: rails_blob_url(file, host: request.base_url),
        filename: file.filename.to_s,
        content_type: file.content_type.to_s
      }
    end

    def dealer_display_name(dealer)
      return "Dealer" unless dealer
      return "#{dealer.dealer_profile.business_name} (#{dealer.dealer_code})" if dealer.dealer_profile&.business_name.present?
      return "Dealer Code: #{dealer.dealer_code}" if dealer.dealer_code.present?

      "Dealer ##{dealer.id}"
    end
  end
end
