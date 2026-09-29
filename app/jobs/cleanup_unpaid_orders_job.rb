class CleanupUnpaidOrdersJob < ApplicationJob
  queue_as :cleanup

  UNPAID_AFTER = 6.hours

  def perform
    # 1. Expire unassigned / broadcast pending orders past their expiry
    Order
      .where(status: "pending")
      .where("expires_at IS NOT NULL AND expires_at < ?", Time.current)
      .find_each do |order|
        cleanup_order(order, reason: "Order expired — no dealer accepted within time limit")
      end

    # 2. Expire unpaid online orders past 6 hours
    Order
      .where(payment_method: "online", status: "pending")
      .where.not(payment_status: "paid")
      .where("placed_at < ? OR (placed_at IS NULL AND created_at < ?)", UNPAID_AFTER.ago, UNPAID_AFTER.ago)
      .find_each do |order|
        cleanup_order(order, reason: "Order auto-cancelled — online payment was never completed within time")
      end
  end

  private

  def cleanup_order(order, reason: "Order auto-cancelled — payment/expiry timeout")
    ActiveRecord::Base.transaction do
      order.reload

      return if order.payment_status == "paid" || order.status != "pending"

      order.dealer_offer&.restore_quantity!(order.total_items) if order.dealer_offer_id.present?

      order.update!(
        status: "cancelled",
        payment_status: order.payment_status == "pending" ? "failed" : order.payment_status,
        cancelled_at: Time.current,
        status_note: [order.status_note, reason].compact.join(" | ")
      )
    end

    notify_buyer(order)
  rescue StandardError => e
    Rails.logger.error("[CleanupUnpaidOrdersJob] order #{order.id}: #{e.message}")
  end

  def notify_buyer(order)
    NotificationService.deliver(
      recipient: order.buyer,
      actor: nil,
      notifiable: order,
      kind: "b2c_order_payment_timeout",
      title: "⏰ Order Cancelled",
      message: "Your order ##{order.order_number} was cancelled because payment was never completed.",
      visible_in_app: true,
      delivery_channels: { push: true, whatsapp: false, sms: false, email: true, in_app: true },
      payload: { order_id: order.order_number, status: "cancelled" }
    )
  rescue StandardError => e
    Rails.logger.error("[CleanupUnpaidOrdersJob] notify buyer for order #{order.id}: #{e.message}")
  end
end
