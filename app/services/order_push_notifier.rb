class OrderPushNotifier
  RETAIL_ENDED_KINDS = %w[order_cancelled b2c_order_expired b2c_order_payment_timeout offer_mart_order_expired].freeze

  class << self

    def retail_placed(order)
      return unless customer_order?(order) && order.payment_method.to_s == "online" && order.dealer_offer_id.blank?

      once(order.buyer, "b2c_order_placed", order) { PushEventsHub.customer_order_placed(order) }
    end

    def retail_accepted(order)
      return unless customer_order?(order) && order.payment_method.to_s == "online" && order.payment_status.to_s == "paid"

      once(order.buyer, "payment_success", order) { PushEventsHub.customer_payment_success(order) }
    end

    def retail_shipped(order)
      return unless customer_order?(order)

      once(order.buyer, "order_dispatched", order) { PushEventsHub.customer_order_dispatched(order) }
    end

    def retail_delivered(order)
      return unless customer_order?(order)

      if order.status.to_s == "replacement_delivered"
        once(order.buyer, "replacement_delivered", order) do
          NotificationService.deliver(
            recipient: order.buyer,
            kind: "replacement_delivered",
            title: "Replacement delivered",
            message: "The replacement for order ##{order.order_number} has been delivered.",
            notifiable: order,
            payload: { order_id: order.id, screen: "CustomerOrderDetails", role: "customer" }
          )
        end
      else
        once(order.buyer, "order_delivered", order) { PushEventsHub.customer_order_delivered(order) }
      end
    end

    def retail_terminated(order, reason = nil)
      return unless customer_order?(order)
      return if RETAIL_ENDED_KINDS.any? { |kind| already_sent?(order.buyer, kind, order) }

      once(order.buyer, "order_cancelled", order) { PushEventsHub.customer_order_cancelled(order, reason) }
    end

    def b2b_shipped(order)
      deliver_to_buyer_dealer(order, "b2b_order_shipped", "Your order has been shipped",
                              "Your B2B order #{reference(order)} has been shipped by the seller.")
    end

    def b2b_delivered(order)
      deliver_to_buyer_dealer(order, "b2b_order_delivered", "Order delivered",
                              "Your B2B order #{reference(order)} has been delivered.")
    end

    def b2b_terminated(order, reason = nil)
      return if order.buyer_dealer && already_sent?(order.buyer_dealer, "b2b_order_expired", order)

      text = "Your B2B order #{reference(order)} has been cancelled."
      text += " Reason: #{reason}." if reason.present?
      deliver_to_buyer_dealer(order, "b2b_order_cancelled", "Order cancelled", text)
    end

    private

    def customer_order?(order)
      order.is_a?(Order) && order.buyer.is_a?(Account)
    end

    def reference(order)
      order.try(:reference_number).presence || "##{order.id}"
    end

    def already_sent?(receiver, kind, notifiable)
      Notification.exists?(receiver: receiver, notification_type: kind, notifiable: notifiable)
    end

    def once(receiver, kind, notifiable)
      return if receiver.blank? || already_sent?(receiver, kind, notifiable)

      yield
    rescue StandardError => e
      Rails.logger.error("[OrderPushNotifier] #{kind} for #{notifiable.class.name}##{notifiable.id} failed: #{e.class}: #{e.message}")
    end

    def deliver_to_buyer_dealer(order, kind, title, message)
      buyer = order.buyer_dealer
      once(buyer, kind, order) do
        NotificationService.deliver(
          recipient: buyer,
          kind: kind,
          title: title,
          message: message,
          notifiable: order,
          payload: { order_id: order.id, order_number: reference(order), order_type: "b2b", screen: "DealerOrders", role: "dealer" }
        )
      end
    end
  end

  singleton_class.public_instance_methods(false).each do |event|
    original = singleton_class.instance_method(event)
    define_singleton_method(event) do |*args, **kwargs, &block|
      original.bind(self).call(*args, **kwargs, &block)
    rescue StandardError => e
      Rails.logger.error("[OrderPushNotifier] #{event} failed: #{e.class}: #{e.message}")
      nil
    end
  end
end
