module Api
  module Admin
    class FlashSalesController < ApplicationController
      include HomeBannerAdmin

      before_action :set_sale, only: [ :show, :update, :destroy, :toggle ]

      def index
        sales = FlashSale.includes(flash_sale_items: :item).order(starts_at: :desc, id: :desc)
        render json: {
          data: sales.map { |s| banner_payload.flash_sale(s, admin: true) },
          max_items: FlashSale::MAX_ITEMS,
          item_types: FlashSaleItem::ITEM_TYPES
        }, status: :ok
      end

      def show
        render json: { data: banner_payload.flash_sale(@sale, admin: true) }, status: :ok
      end

      def create
        sale = FlashSale.new(sale_params)
        save_with_items(sale, status: :created, message: "Flash sale created")
      end

      def update
        @sale.assign_attributes(sale_params)
        save_with_items(@sale, status: :ok, message: "Flash sale updated")
      end

      # PATCH /api/admin/flash_sales/:id/toggle — show/hide on the storefront
      def toggle
        @sale.update!(is_active: !@sale.is_active)
        render json: {
          data: banner_payload.flash_sale(@sale.reload, admin: true),
          message: @sale.is_active ? "Flash sale is now visible" : "Flash sale hidden"
        }, status: :ok
      end

      def destroy
        @sale.destroy
        render json: { message: "Flash sale deleted" }, status: :ok
      end

      # GET /api/admin/flash_sales/item_options?item_type=Product&search=iphone
      def item_options
        search = params[:search].to_s.strip
        records =
          case params[:item_type]
          when "DealerOffer"
            scope = DealerOffer.visible_to_marketplace.includes(:product_variant, media_attachments: :blob)
            scope = scope.where("dealer_offers.device_model ILIKE :q OR dealer_offers.seller_code ILIKE :q", q: "%#{search}%") if search.present?
            scope.order(created_at: :desc).limit(25)
          else
            scope = Product.active.includes(:category, :brand, :product_variants, media_attachments: :blob)
            scope = scope.where("products.name ILIKE ?", "%#{search}%") if search.present?
            scope.order(created_at: :desc).limit(25)
          end

        type = params[:item_type] == "DealerOffer" ? "DealerOffer" : "Product"
        data = records.map do |r|
          { item_type: type, item_id: r.id, available: FlashSaleItem.sellable?(r) }.merge(banner_payload.item_details(r) || {})
        end
        render json: { data: data }, status: :ok
      end

      private

      def sale_params
        permitted = params.require(:flash_sale).permit(
          :title, :badge_text, :subtitle, :starts_at, :ends_at, :is_active, :show_countdown, :position
        )
        blank_to_nil!(permitted, :starts_at, :ends_at)
      end

      # items: [{ item_type: "Product", item_id: 12, label: "HOT DEAL" }, ...] — replaces the whole list when sent.
      def items_param
        return nil unless params[:flash_sale]&.key?(:items)

        Array(params[:flash_sale][:items]).map do |raw|
          raw = raw.respond_to?(:permit) ? raw.permit(:item_type, :item_id, :label) : raw
          { item_type: raw[:item_type].to_s, item_id: raw[:item_id].to_i, label: raw[:label].to_s.strip.presence }
        end
      end

      def save_with_items(sale, status:, message:)
        items = items_param
        item_error = items && validate_items(items)
        return render json: { error: [ item_error ] }, status: :unprocessable_entity if item_error

        FlashSale.transaction do
          sale.save!
          if items
            # Replace the whole list; the transaction restores the old list if anything fails.
            sale.flash_sale_items.delete_all
            items.each_with_index do |i, index|
              sale.flash_sale_items.create!(item_type: i[:item_type], item_id: i[:item_id], label: i[:label], position: index)
            end
          end
        end

        fresh = FlashSale.includes(flash_sale_items: :item).find(sale.id)
        render json: { data: banner_payload.flash_sale(fresh, admin: true), message: message }, status: status
      rescue ActiveRecord::RecordInvalid => e
        messages = e.record.errors.full_messages.presence || [ "Could not save flash sale" ]
        render json: { error: messages.uniq }, status: :unprocessable_entity
      end

      def validate_items(items)
        return "A flash sale can have at most #{FlashSale::MAX_ITEMS} items" if items.size > FlashSale::MAX_ITEMS
        return "The same item was added twice" if items.uniq { |i| [ i[:item_type], i[:item_id] ] }.size != items.size

        missing = items.find { |i| !FlashSaleItem::ITEM_TYPES.include?(i[:item_type]) || !i[:item_type].constantize.exists?(i[:item_id]) }
        "One of the selected items no longer exists" if missing
      end

      def set_sale
        @sale = FlashSale.includes(flash_sale_items: :item).find_by(id: params[:id])
        render json: { error: "Flash sale not found" }, status: :not_found unless @sale
      end
    end
  end
end
