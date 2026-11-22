class OfferMartSellerResponseService
  class NotAllowed < StandardError; end

  REASON = "Rejected by the seller".freeze
  NOTICE_REASON = "rejected by seller".freeze

  def initialize(order:, dealer:)
    @order = order
    @dealer = dealer
  end

  def accept!
    @order.with_lock do
      ensure_own_offer_order!
      raise NotAllowed, "This order is already cancelled." if @order.status.to_s == "cancelled"
    end

    PushNotificationService.cancel_ring(@order)
    @order
  end

  def reject!
    @order.with_lock do
      ensure_own_offer_order!
      raise NotAllowed, "This order is already cancelled." if @order.status.to_s == "cancelled"
      raise NotAllowed, "This order is already #{@order.status.to_s.humanize.downcase}, so it can no longer be rejected." unless @order.status.to_s == "processing"

      if @order.payment_method.to_s == "online" && @order.payment_status.to_s.in?(%w[paid partially_refunded])
        refunded = InstantOrderRefundService.process_refund!(order: @order, reason: REASON, notify: false)
        raise NotAllowed, "We could not start the buyer's refund right now, so the order was not rejected. Please try again in a minute." unless refunded
      end

      OrderLifecycleService.new(order: @order, actor: @dealer, status_note: REASON).transition!(next_status: "cancelled")
    end

    notify_after_reject
    @order.reload
  end

  private

  def ensure_own_offer_order!
    return if @order.dealer_offer_id.present? && @order.seller_dealer_id == @dealer.id

    raise NotAllowed, "This order is not available."
  end

  def notify_after_reject
    PushNotificationService.cancel_ring(@order)
    EmailDispatcherService.retail_order_terminated(@order, NOTICE_REASON)

    return unless @order.buyer.is_a?(Dealer)

    NotificationService.deliver(
      recipient: @order.buyer,
      kind: "order_cancelled",
      title: "Order cancelled",
      message: "Your order ##{@order.order_number} was rejected by the seller and has been cancelled." +
               (@order.payment_status.to_s == "refunded" ? " Your payment will be refunded to the original payment method." : ""),
      notifiable: @order,
      payload: { order_id: @order.id, screen: "DealerOrders", role: "dealer" }
    )
  rescue StandardError => e
    Rails.logger.warn("[OfferMartSellerResponseService] notifications failed for Order##{@order.id}: #{e.message}")
  end
end
