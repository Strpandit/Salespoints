module Api
  module Admin
    class OrdersController < ApplicationController
      before_action :require_admin!

      # Validates per_page itself (422 on <1); skip the base controller's silent fallback.
      def strict_per_page?
        true
      end
      private :strict_per_page?

      DELIVERY_CONFIRMATION_PRELOADS = {
        product_with_customer_image_attachment: :blob,
        product_packaging_image_attachment: :blob,
        product_open_box_images_attachments: :blob
      }.freeze

      RETAIL_PRELOADS = [
        :buyer, :seller_dealer, :return_requests,
        { order_items: [:product_variant_color, { product_variant: { product: { media_attachments: :blob } } }] },
        { delivery_confirmation: DELIVERY_CONFIRMATION_PRELOADS },
        { replacement_delivery_confirmation: DELIVERY_CONFIRMATION_PRELOADS }
      ].freeze

      B2B_PRELOADS = [
        :buyer_dealer, :seller_dealer,
        { b2b_order_items: [:product_variant_color, :dealer_product, { wholesaler_post: { media_attachments: :blob } }, { product_variant: { product: { media_attachments: :blob } } }] },
        { delivery_confirmation: DELIVERY_CONFIRMATION_PRELOADS },
        { replacement_delivery_confirmation: DELIVERY_CONFIRMATION_PRELOADS }
      ].freeze

      def index
        # Filtering/sorting/pagination run on lightweight rows; only the requested page is loaded and serialised.
        retail_orders = Order.all
        b2b_orders = B2bOrder.all

        # ===== ORDER TYPE FILTER =====
        if params[:order_type].present?
          if params[:order_type] == "retail"
            b2b_orders = B2bOrder.none
          elsif params[:order_type] == "b2b"
            retail_orders = Order.none
          end
        end

        # ===== STATUS FILTER =====
        if params[:status].present? && params[:status] != "all"
          retail_orders = retail_orders.where(status: params[:status])
          b2b_orders = b2b_orders.where(status: params[:status])
        end

        # ===== B2B REQUEST STATUS FILTER =====
        if params[:request_status].present? && params[:request_status] != "all"
          b2b_orders = b2b_orders.where(request_status: params[:request_status])
        end

        # ===== SOURCE FILTER (B2B only) =====
        if params[:source_type].present? && params[:source_type] != "all"
          b2b_orders = b2b_orders.where(source_type: params[:source_type])
        end

        # ===== B2B DIRECT BUY FILTER =====
        if params[:is_direct_buy].present?
          is_direct = ActiveModel::Type::Boolean.new.cast(params[:is_direct_buy])
          b2b_orders = b2b_orders.where(is_direct_buy: is_direct)
        end

        # ===== DATE FILTER =====
        begin
          if params[:date_from].present?
            from = Date.parse(params[:date_from].to_s).beginning_of_day
            retail_orders = retail_orders.where("orders.created_at >= ?", from)
            b2b_orders = b2b_orders.where("b2b_orders.created_at >= ?", from)
          end

          if params[:date_to].present?
            to = Date.parse(params[:date_to].to_s).end_of_day
            retail_orders = retail_orders.where("orders.created_at <= ?", to)
            b2b_orders = b2b_orders.where("b2b_orders.created_at <= ?", to)
          end
        rescue ArgumentError, TypeError
          return render json: { error: "Invalid date_from/date_to: expected a valid date (YYYY-MM-DD)" }, status: :unprocessable_entity
        end

        # ===== PAGINATION PARAMS =====
        page = [[params[:page].to_i, 1].max, 1_000_000].min
        if params[:per_page].to_s.strip.empty?
          per_page = 20
        else
          per_page = Integer(params[:per_page].to_s.strip, 10, exception: false)
          if per_page.nil? || per_page < 1
            return render json: { error: "per_page must be a positive integer" }, status: :unprocessable_entity
          end
          per_page = [per_page, 100].min
        end

        # ===== SEARCH =====
        if params[:search].present?
          query = "%#{params[:search].strip}%"

          # Retail search
          retail_orders = retail_orders
            .joins("LEFT JOIN accounts ON orders.buyer_id = accounts.id AND orders.buyer_type = 'Account'")
            .joins("LEFT JOIN dealers AS buyer_dealers ON orders.buyer_id = buyer_dealers.id AND orders.buyer_type = 'Dealer'")
            .where(
              "orders.order_number ILIKE :q OR accounts.email ILIKE :q OR accounts.first_name ILIKE :q OR accounts.phone ILIKE :q OR buyer_dealers.email ILIKE :q OR buyer_dealers.first_name ILIKE :q OR buyer_dealers.dealer_code ILIKE :q OR buyer_dealers.phone ILIKE :q",
              q: query
            )

          # B2B search
          b2b_orders = b2b_orders
            .joins("LEFT JOIN dealers AS buyers ON b2b_orders.buyer_dealer_id = buyers.id")
            .joins("LEFT JOIN dealers AS sellers ON b2b_orders.seller_dealer_id = sellers.id")
            .where(
              "b2b_orders.reference_number ILIKE :q OR buyers.email ILIKE :q OR buyers.first_name ILIKE :q OR buyers.dealer_code ILIKE :q OR buyers.phone ILIKE :q OR sellers.dealer_code ILIKE :q",
              q: query
            )
        end

        # ===== LIGHTWEIGHT ROWS (just what filtering/sorting needs) =====
        rows = []
        retail_orders.pluck("orders.id", "orders.created_at", "orders.total_amount", "orders.payment_method").each do |id, created_at, total, pm|
          rows << { type: "retail", id: id, created_at: created_at.iso8601, total_amount: total.to_f, payment_method: pm }
        end
        b2b_orders.pluck("b2b_orders.id", "b2b_orders.created_at", "b2b_orders.total_amount", "b2b_orders.payment_method").each do |id, created_at, total, pm|
          rows << { type: "b2b", id: id, created_at: created_at.iso8601, total_amount: total.to_f, payment_method: pm }
        end

        # ===== PAYMENT METHOD FILTER =====
        if params[:payment_method].present? && params[:payment_method] != "all"
          if params[:payment_method] == "online"
            rows = rows.select { |o| %w[online razorpay upi card netbanking].include?(o[:payment_method].to_s.downcase) || (o[:payment_method].to_s.downcase != "cod" && o[:payment_method].to_s.downcase != "cash") }
          elsif params[:payment_method] == "cod"
            rows = rows.select { |o| %w[cod cash pay_on_delivery].include?(o[:payment_method].to_s.downcase) || o[:payment_method].blank? }
          end
        end

        # ===== AMOUNT RANGE FILTER =====
        if params[:min_amount].present?
          rows = rows.select { |o| o[:total_amount].to_f >= params[:min_amount].to_f }
        end
        if params[:max_amount].present?
          rows = rows.select { |o| o[:total_amount].to_f <= params[:max_amount].to_f }
        end

        # ===== SORTING =====
        case params[:sort_by]
        when "oldest"
          rows = rows.sort_by { |o| o[:created_at] }
        when "amount_desc"
          rows = rows.sort_by { |o| o[:total_amount].to_f }.reverse
        when "amount_asc"
          rows = rows.sort_by { |o| o[:total_amount].to_f }
        else
          rows = rows.sort_by { |o| o[:created_at] }.reverse
        end

        # ===== PAGINATION =====
        total_count = rows.length
        page_rows = rows[(page - 1) * per_page, per_page] || []

        # ===== LOAD + SERIALISE ONLY THE PAGE =====
        retail_ids = page_rows.select { |r| r[:type] == "retail" }.map { |r| r[:id] }
        b2b_ids = page_rows.select { |r| r[:type] == "b2b" }.map { |r| r[:id] }
        retail_by_id = retail_ids.empty? ? {} : Order.includes(*RETAIL_PRELOADS).where(id: retail_ids).index_by(&:id)
        b2b_by_id = b2b_ids.empty? ? {} : B2bOrder.includes(*B2B_PRELOADS).where(id: b2b_ids).index_by(&:id)

        paginated = page_rows.filter_map do |r|
          if r[:type] == "retail"
            order = retail_by_id[r[:id]]
            order && transform_retail_order(order)
          else
            order = b2b_by_id[r[:id]]
            order && transform_b2b_order(order)
          end
        end

        render json: {
          data: paginated,
          meta: {
            current_page: page,
            next_page: page * per_page < total_count ? page + 1 : nil,
            prev_page: page > 1 ? page - 1 : nil,
            total_pages: (total_count.to_f / per_page).ceil,
            total_count: total_count
          },
          message: "Orders fetched successfully"
        }, status: :ok
      end

      # Retail (orders) and B2B (b2b_orders) ids overlap, so callers pass order_type to pick the table.
      def show
        unless requested_order_type == "b2b"
          order = Order.includes(:buyer, :seller_dealer, order_items: { product_variant: :product })
                       .find_by(id: params[:id])
          return render json: { data: transform_retail_order(order) }, status: :ok if order.present?
        end

        unless requested_order_type == "retail"
          b2b_order = B2bOrder.includes(:buyer_dealer, :seller_dealer, b2b_order_items: { product_variant: :product })
                              .find_by(id: params[:id])
          return render json: { data: transform_b2b_order(b2b_order) }, status: :ok if b2b_order.present?
        end

        render json: { error: "Order not found" }, status: :not_found
      end

      def download_invoice
        begin
          return render json: { error: "Unauthorized" }, status: :unauthorized unless current_admin.present?
          order =
            case requested_order_type
            when "retail" then Order.find_by(id: params[:id])
            when "b2b" then B2bOrder.find_by(id: params[:id])
            else Order.find_by(id: params[:id]) || B2bOrder.find_by(id: params[:id])
            end

          return render json: { error: "Order not found" }, status: :not_found unless order
          unless %w[delivered replacement_requested replacement_approved replacement_shipped replacement_delivered].include?(order.status)
            return render json: { error: "Invoice can only be generated for delivered orders" }, status: :unprocessable_entity
          end
  
          generator = ::InvoicePdf.new(order)

          send_data generator.generate,
                    filename: "Invoice_#{order.reload.invoice_number}.pdf",
                    type: "application/pdf",
                    disposition: "attachment"

        rescue StandardError => e
          render json: { error: "Failed to generate invoice" }, status: :internal_server_error
        end
      end

      private

      # nil when an older client did not send it (then the legacy retail-first lookup applies).
      def requested_order_type
        type = params[:order_type].to_s
        %w[retail b2b].include?(type) ? type : nil
      end

      def transform_retail_order(order)
        {
          id: order.id,
          order_type: "retail",
          order_number: order.order_number,
          status: order.status,
          total_amount: order.total_amount.to_f,
          created_at: order.created_at.iso8601,
          items_count: order.order_items.sum { |i| i.quantity.to_i },
          
          # Customer Info
          customer_name: order.buyer&.full_name || order.buyer&.first_name || "Customer",
          customer_email: order.buyer&.email,
          buyer_type: order.buyer_type,
          buyer_id: order.buyer_id,
          
          # Seller Info
          seller_dealer_id: order.seller_dealer_id,
          seller_name: order.seller_dealer&.full_name || order.seller_dealer&.dealer_code,
          seller_dealer_code: order.seller_dealer&.dealer_code,
          
          # Payment
          payment_method: order.payment_method,
          payment_status: order.payment_status,
          payment_reference: order.payment_reference,
          
          # Settlement
          settlement_status: order.settlement_status,
          seller_settlement_amount: order.seller_settlement_amount.to_f,
          refund_amount: order.refund_amount.to_f,
          refund_status: order.refund_status,
          
          # Addresses
          billing_address: order.billing_address,
          shipping_address: order.shipping_address,
          
          # Timestamps
          placed_at: order.placed_at&.iso8601,
          processing_at: order.processing_at&.iso8601,
          shipped_at: order.shipped_at&.iso8601,
          delivered_at: order.delivered_at&.iso8601,
          cancelled_at: order.cancelled_at&.iso8601,
          
          # Items
          order_items: order.order_items.map do |item|
            {
              id: item.id,
              product_name: item.product_name,
              product_name_with_variant: item.product_name_with_variant,
              quantity: item.quantity,
              unit_price: item.unit_price.to_f,
              total_price: item.total_price.to_f,
              image_url: order_item_image_url(item)
            }
          end,
          
          # Return Requests
          return_requests: order.return_requests.map do |rr|
            {
              id: rr.id,
              request_type: rr.request_type,
              status: rr.status,
              reason: rr.reason,
              resolution_notes: rr.resolution_notes
            }
          end,

          # Delivery Confirmation & Proof Images
          delivery_confirmation: delivery_confirmation_payload(order.delivery_confirmation),
          replacement_delivery_confirmation: delivery_confirmation_payload(order.replacement_delivery_confirmation)
        }
      end

      def transform_b2b_order(order)
        {
          id: order.id,
          order_type: "b2b",
          reference_number: order.reference_number,
          status: order.status,
          request_status: order.request_status,
          total_amount: order.total_amount.to_f,
          subtotal_amount: order.subtotal_amount.to_f,
          tax_amount: order.tax_amount.to_f,
          created_at: order.created_at.iso8601,
          
          # Buyer Info
          buyer_dealer_id: order.buyer_dealer_id,
          buyer_dealer_name: order.buyer_dealer&.full_name || order.buyer_dealer&.dealer_code,
          buyer_dealer_code: order.buyer_dealer&.dealer_code,
          
          # Seller Info
          seller_dealer_id: order.seller_dealer_id,
          seller_dealer_name: order.seller_dealer&.full_name || order.seller_dealer&.dealer_code,
          seller_dealer_code: order.seller_dealer&.dealer_code,
          
          # Source
          source_type: order.source_type,
          is_direct_buy: order.is_direct_buy,
          
          # Payment
          payment_method: order.payment_method,
          payment_status: order.payment_status,
          payment_token: order.payment_token,

          # Addresses
          billing_address: order.billing_address,
          shipping_address: order.shipping_address,
          
          # Timestamps
          requested_at: order.requested_at&.iso8601,
          accepted_at: order.accepted_at&.iso8601,
          confirmed_at: order.confirmed_at&.iso8601,
          payment_confirmed_at: order.payment_confirmed_at&.iso8601,
          payment_link_sent_at: order.payment_link_sent_at&.iso8601,
          shipped_at: order.shipped_at&.iso8601,
          delivered_at: order.delivered_at&.iso8601,
          cancelled_at: order.cancelled_at&.iso8601,
          rejected_at: order.rejected_at&.iso8601,
          expired_at: order.expires_at&.iso8601,
          
          # Items
          b2b_order_items: order.b2b_order_items.map do |item|
            {
              id: item.id,
              product_name: item.product_variant&.product&.name || "Product",
              variant_sku: item.product_variant&.variant_sku,
              quantity: item.quantity,
              unit_price: item.unit_price.to_f,
              total_price: item.total_price.to_f,
              status: item.status,
              image_url: b2b_item_image_url(item)
            }
          end,

          # Delivery Confirmation & Proof Images
          delivery_confirmation: delivery_confirmation_payload(order.delivery_confirmation),
          replacement_delivery_confirmation: delivery_confirmation_payload(order.replacement_delivery_confirmation)
        }
      end

      def order_item_image_url(item)
        pv = item.try(:product_variant)
        dp = item.try(:dealer_product)
        blob = pv&.media&.first&.blob || pv&.product&.media&.first&.blob || dp&.media&.first&.blob || dp&.product_variant&.media&.first&.blob || dp&.product&.media&.first&.blob
        return nil unless blob
        host = request.base_url.to_s.sub(%r{\Ahttp://}, "https://")
        url = Rails.application.routes.url_helpers.rails_blob_url(blob, host: host, protocol: "https")
        url.to_s.sub(%r{\Ahttp://}, "https://")
      rescue StandardError
        nil
      end

      def b2b_item_image_url(item)
        blob = if item.try(:wholesaler_post_id).present?
                 item.wholesaler_post&.media&.first&.blob
               elsif item.try(:dealer_product_id).present?
                 dp = item.dealer_product
                 dp&.media&.first&.blob || dp&.product_variant&.media&.first&.blob || dp&.product&.media&.first&.blob
               elsif item.try(:product_variant_id).present?
                 pv = item.product_variant
                 pv&.media&.first&.blob || pv&.product&.media&.first&.blob
               end
        return nil unless blob
        host = request.base_url.to_s.sub(%r{\Ahttp://}, "https://")
        url = Rails.application.routes.url_helpers.rails_blob_url(blob, host: host, protocol: "https")
        url.to_s.sub(%r{\Ahttp://}, "https://")
      rescue StandardError
        nil
      end

      def delivery_confirmation_payload(dc)
        return nil unless dc.present?

        {
          id: dc.id,
          token: dc.token,
          context: dc.context,
          status: dc.status,
          notes: dc.notes,
          buyer_name: dc.buyer_name,
          seller_name: dc.seller_name,
          buyer_phone: dc.buyer_phone,
          seller_phone: dc.seller_phone,
          buyer_otp_verified: dc.buyer_verified?,
          submitted_at: dc.submitted_at&.iso8601,
          completed_at: dc.completed_at&.iso8601,
          declarations: dc.declarations,
          uploads: {
            product_with_customer_image: attachment_payload(dc.product_with_customer_image),
            product_packaging_image: attachment_payload(dc.product_packaging_image),
            product_open_box_images: (dc.product_open_box_images || []).map { |file| attachment_payload(file) }.compact
          }
        }
      end

      def attachment_payload(file)
        return nil if file.blank?

        if file.respond_to?(:attached?)
          return nil unless file.attached?
          file = file.attachment
        end

        blob = file.respond_to?(:blob) ? file.blob : file
        return nil if blob.blank? || !blob.respond_to?(:filename)

        {
          filename: blob.filename.to_s,
          content_type: blob.content_type,
          byte_size: blob.byte_size,
          url: Rails.application.routes.url_helpers.rails_blob_url(blob, only_path: false)
        }
      rescue StandardError
        nil
      end

      def require_admin!
        unless current_admin.present?
          return render json: { error: "Unauthorized. Admin access required." }, status: :unauthorized
        end

        unless current_admin.can_access?(:orders, :read)
          render json: { error: "You do not have permission to view orders" }, status: :forbidden
        end
      end
    end
  end
end