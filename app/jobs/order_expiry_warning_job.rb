class OrderExpiryWarningJob < ApplicationJob
  queue_as :default

  WARN_WITHIN = 10.minutes

  def perform
    now = Time.current
    horizon = now + WARN_WITHIN

    retail = OrderOffer.open_state
                       .where(expires_at: now..horizon)
                       .joins(:order)
                       .where(orders: { status: "pending", seller_dealer_id: nil })
                       .includes(:order, :dealer)
    warn_dealers(retail, :order, now)

    b2b = B2bOrderOffer.open_state
                       .where(expires_at: now..horizon)
                       .joins(:b2b_order)
                       .where(b2b_orders: { request_status: "pending_request" })
                       .includes(:b2b_order, :dealer)
    warn_dealers(b2b, :b2b_order, now)
  end

  private

  def warn_dealers(offers, order_association, now)
    offers.find_each do |offer|
      dealer = offer.dealer
      order = offer.public_send(order_association)
      next unless dealer&.active? && order

      next if Notification.exists?(receiver: dealer, notifiable: order, notification_type: "order_expiring_soon")

      minutes_left = [((offer.expires_at - now) / 60.0).ceil, 1].max
      PushEventsHub.dealer_order_expiring_soon(dealer, order, minutes_left)
    rescue StandardError => e
      Rails.logger.warn("[OrderExpiryWarningJob] offer ##{offer.id} failed: #{e.class}: #{e.message}")
    end
  end
end
