class PaymentAmountGuard
  TOLERANCE = 1.to_d
  REVIEW_KEY = "amount_mismatch_review".freeze

  class << self
    def enabled?
      ENV["BLOCK_PAYMENT_AMOUNT_MISMATCH"].to_s.downcase == "true"
    end

    def mismatch?(expected, received)
      return false if received.blank?

      (BigDecimal(expected.to_s) - BigDecimal(received.to_s)).abs > TOLERANCE
    rescue ArgumentError, TypeError
      false
    end

    def hold_attempt?(attempt, expected, received, gateway_payload = nil)
      return false unless enabled?
      return true if held_attempt?(attempt)
      return false unless mismatch?(expected, received)

      payload = (attempt.result_payload || {}).merge(REVIEW_KEY => review_entry(expected, received))
      attributes = { result_payload: payload }
      attributes[:payment_gateway_payload] = (attempt.payment_gateway_payload || {}).merge(gateway_payload) if gateway_payload.is_a?(Hash)
      attempt.update!(attributes)
      notify_admins(attempt, expected, received)
      true
    end

    def held_attempt?(attempt)
      enabled? && (attempt.result_payload || {})[REVIEW_KEY].present?
    end

    def hold_order?(order, expected, received, gateway_payload = nil)
      return false unless enabled?
      return true if (order.payment_gateway_payload || {})[REVIEW_KEY].present?
      return false unless mismatch?(expected, received)

      payload = (order.payment_gateway_payload || {}).merge(REVIEW_KEY => review_entry(expected, received))
      payload = payload.merge(gateway_payload) if gateway_payload.is_a?(Hash)
      order.update!(payment_gateway_payload: payload)
      notify_admins(order, expected, received)
      true
    end

    private

    def review_entry(expected, received)
      { "expected_amount" => expected.to_f, "received_amount" => received.to_f, "flagged_at" => Time.current.iso8601 }
    end

    def notify_admins(record, expected, received)
      label = record.try(:order_number) || record.try(:attempt_number) || "##{record.id}"
      AdminUser.where(is_super_admin: true).find_each do |admin|
        NotificationService.deliver(
          recipient: admin,
          actor: nil,
          notifiable: record,
          kind: "admin_payment_amount_mismatch",
          title: "Payment held: amount mismatch",
          message: "Cashfree confirmed Rs #{received} for #{record.class.name} #{label}, but Rs #{expected} was expected. It has NOT been finalised and needs manual review.",
          visible_in_app: true,
          delivery_channels: { push: true, whatsapp: false, sms: false, email: true, in_app: true },
          payload: { expected_amount: expected.to_f, received_amount: received.to_f, held_for_review: true }
        )
      end
    rescue StandardError => e
      Rails.logger.error("[PaymentAmountGuard] failed to notify admins: #{e.message}")
    end
  end
end
