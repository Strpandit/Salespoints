class OfferMartPaymentService
  class << self
    def offer_order?(order)
      order.dealer_offer_id.present?
    end

    def confirm_paid!(order)
      order.with_lock do
        order.reload
        if order.status == "cancelled"
          return refund_late_payment!(order) unless reserve_again!(order)
        elsif order.status == "pending"
          OrderLifecycleService.new(order: order, actor: order.buyer, status_note: "Online payment confirmed successfully.")
                               .transition!(next_status: "processing")
          order.update_columns(accepted_at: order.accepted_at || Time.current)
        end
      end

      notify_seller_and_buyer(order.reload)
      safe { EmailDispatcherService.retail_order_placed(order) }
      order
    end

    def release_unpaid!(order, reason: "Payment cancelled")
      released = false
      order.with_lock do
        next unless offer_order?(order)
        next unless order.status == "pending" && order.payment_status != "paid"

        order.dealer_offer&.restore_quantity!(order.total_items)
        order.update!(
          status: "cancelled",
          payment_status: order.payment_status == "pending" ? "failed" : order.payment_status,
          cancelled_at: Time.current,
          status_note: "Offer Mart order cancelled — #{reason}"
        )
        released = true
      end
      released
    end

    private

    def reserve_again!(order)
      offer = order.dealer_offer
      return false unless offer && offer.dealer&.status == "active"

      offer.deduct_quantity!(order.total_items)
      order.update!(
        status: "processing",
        cancelled_at: nil,
        accepted_at: Time.current,
        processing_at: Time.current,
        status_note: "Payment received after the reservation window — stock re-reserved"
      )
      true
    rescue StandardError => e
      Rails.logger.warn("[OfferMartPaymentService] re-reserve failed for order #{order.id}: #{e.message}")
      false
    end

    def refund_late_payment!(order)
      refunded = InstantOrderRefundService.process_refund!(
        order: order,
        reason: "Offer Mart payment received after the offer sold out or the reservation expired"
      )
      return order if refunded

      AdminUser.where(is_super_admin: true).find_each do |admin|
        NotificationService.deliver(
          recipient: admin,
          actor: nil,
          notifiable: order,
          kind: "admin_payment_amount_mismatch",
          title: "⚠️ Manual refund needed",
          message: "Order ##{order.order_number} was paid ₹#{order.total_amount} after its Offer Mart stock was released and could not be re-reserved or auto-refunded.",
          visible_in_app: true,
          delivery_channels: { push: true, whatsapp: false, sms: false, email: true, in_app: true }
        )
      end
      order
    end

    def notify_seller_and_buyer(order)
      offer = order.dealer_offer
      return unless offer && order.status == "processing"

      address = (order.shipping_address || {}).to_h.stringify_keys
      OfferMartBuyNowService.new(
        buyer: order.buyer,
        dealer_offer: offer,
        quantity: order.total_items,
        payment_method: order.payment_method,
        shipping_address: address,
        billing_address: order.billing_address,
        pincode: address["postal_code"]
      ).notify_paid_order(order, offer)
    end

    def safe
      yield
    rescue StandardError => e
      Rails.logger.warn("[OfferMartPaymentService] #{e.message}")
    end
  end
end
