class BuyerOrderCancellationService
  class NotCancellable < StandardError; end

  Result = Struct.new(:order, :refunded, keyword_init: true)

  REASON = "Cancelled by buyer before a seller accepted".freeze
  NOTICE_REASON = "cancelled by buyer".freeze

  class << self
    def cancellable?(order)
      case order
      when Order then retail_cancellable?(order)
      when B2bOrder then b2b_cancellable?(order)
      else false
      end
    end

    def retail_cancellable?(order)
      order.status.to_s == "pending" && order.seller_dealer_id.blank? && order.dealer_offer_id.blank?
    end

    def b2b_cancellable?(order)
      order.request_status.to_s == "pending_request" && order.status.to_s == "pending_request" &&
        order.accepted_at.blank? && order.payment_status.to_s != "paid"
    end
  end

  def initialize(order:)
    @order = order
  end

  def call
    @order.is_a?(B2bOrder) ? cancel_b2b! : cancel_retail!
  end

  private

  def cancel_retail!
    refunded = false
    missed_dealer_ids = []

    @order.with_lock do
      raise NotCancellable, retail_blocked_message unless self.class.retail_cancellable?(@order)

      paid_online = @order.payment_method.to_s == "online" && @order.payment_status.to_s.in?(%w[paid partially_refunded])
      if paid_online
        refunded = InstantOrderRefundService.process_refund!(order: @order, reason: REASON, notify: false)
        unless refunded
          raise NotCancellable, "We could not start your refund right now, so the order was not cancelled. Please try again in a minute."
        end
      end

      attrs = {
        status: "cancelled",
        cancelled_at: Time.current,
        status_note: [@order.status_note, REASON].compact_blank.join(" | ")
      }
      attrs[:payment_status] = "failed" if @order.payment_status.to_s == "pending"
      @order.update!(attrs)

      missed_dealer_ids = @order.order_offers.open_state.pluck(:dealer_id)
      @order.order_offers.open_state.update_all(status: "cancelled", responded_at: Time.current)
      @order.order_broadcast_trackers.pending.update_all(status: "expired")
    end

    notify_after_cancel(missed_dealer_ids) do
      EmailDispatcherService.retail_order_terminated(@order, NOTICE_REASON)
      notify_dealer_buyer(refunded)
    end

    Result.new(order: @order.reload, refunded: refunded)
  end

  def cancel_b2b!
    missed_dealer_ids = []

    @order.with_lock do
      raise NotCancellable, b2b_blocked_message unless self.class.b2b_cancellable?(@order)

      @order.update!(
        status: "cancelled",
        request_status: "cancelled_request",
        cancelled_at: Time.current,
        status_note: [@order.status_note, REASON].compact_blank.join(" | ")
      )

      missed_dealer_ids = @order.b2b_order_offers.open_state.pluck(:dealer_id)
      @order.b2b_order_offers.open_state.update_all(status: "cancelled", responded_at: Time.current)
      @order.dealer_broadcast_trackers.pending.update_all(status: "expired")
    end

    notify_after_cancel(missed_dealer_ids) do
      EmailDispatcherService.b2b_order_terminated(@order, NOTICE_REASON)
    end

    Result.new(order: @order.reload, refunded: false)
  end

  # Everything here is best effort: the cancellation has already happened and must not fail because a push or an
  # email could not be sent.
  def notify_after_cancel(dealer_ids)
    Dealer.where(id: dealer_ids).find_each do |dealer|
      PushEventsHub.dealer_order_cancelled_by_buyer(dealer, @order)
    rescue StandardError => e
      Rails.logger.warn("[BuyerOrderCancellationService] could not tell dealer ##{dealer.id} about #{@order.class.name}##{@order.id}: #{e.message}")
    end

    # Stops the ringing alert on every dealer's phone.
    PushNotificationService.cancel_ring(@order)

    yield if block_given?
  rescue StandardError => e
    Rails.logger.warn("[BuyerOrderCancellationService] notifications failed for #{@order.class.name}##{@order.id}: #{e.message}")
  end

  # A dealer buying a retail product has no customer push from the order mailer path, so tell them directly.
  def notify_dealer_buyer(refunded)
    return unless @order.buyer.is_a?(Dealer)

    NotificationService.deliver(
      recipient: @order.buyer,
      kind: "order_cancelled",
      title: "Order cancelled",
      message: "Your order ##{@order.order_number} has been cancelled." +
               (refunded ? " Your payment will be refunded to the original payment method." : ""),
      notifiable: @order,
      payload: { order_id: @order.id, screen: "DealerOrders", role: "dealer" }
    )
  end

  def retail_blocked_message
    if @order.status.to_s == "cancelled"
      "This order is already cancelled."
    elsif @order.dealer_offer_id.present? || @order.seller_dealer_id.present? || @order.status.to_s != "pending"
      "A seller has already accepted this order, so it can no longer be cancelled here."
    else
      "This order can no longer be cancelled."
    end
  end

  def b2b_blocked_message
    if @order.status.to_s == "cancelled"
      "This request is already cancelled."
    elsif @order.payment_status.to_s == "paid"
      "This order is already paid. Please contact support to cancel it."
    else
      "A seller has already responded to this request, so it can no longer be cancelled here."
    end
  end
end
