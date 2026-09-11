class ExpireOfferMartOrderJob < ApplicationJob
  queue_as :default

  # Releases the reserved offer stock when an online Offer Mart payment is never completed.
  def perform(order_id)
    order = Order.find_by(id: order_id)
    return unless order
    return if order.dealer_offer_id.blank?
    return unless order.status == "pending"
    return if order.payment_status == "paid"

    ActiveRecord::Base.transaction do
      order.dealer_offer&.restore_quantity!(order.total_items)
      order.update!(
        status: "cancelled",
        payment_status: order.payment_status == "pending" ? "failed" : order.payment_status,
        cancelled_at: Time.current,
        status_note: "Offer Mart order cancelled — payment not completed in time"
      )
    end

    NotificationService.deliver(
      recipient: order.buyer,
      actor: nil,
      notifiable: order,
      kind: "offer_mart_order_expired",
      title: "⏰ Order Expired",
      message: "Your order ##{order.order_number} was cancelled because the payment was not completed in time.",
      visible_in_app: true,
      delivery_channels: { push: true, whatsapp: false, sms: false, email: true, in_app: true },
      payload: { order_id: order.order_number, status: "cancelled" }
    )
  rescue StandardError => e
    Rails.logger.error("[ExpireOfferMartOrderJob] order #{order_id}: #{e.message}")
  end
end
