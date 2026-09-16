class CleanupStuckPaymentAttemptsJob < ApplicationJob
  queue_as :cleanup

  STALE_AFTER = 2.hour

  def perform
    PaymentAttempt.where(status: "pending").where("created_at < ?", STALE_AFTER.ago).find_each do |attempt|
      cleanup_attempt(attempt)
    end
  end

  private

  def cleanup_attempt(attempt)
    if attempt.gateway_order_reference.present?
      gateway_status = fetch_gateway_status(attempt)
      return if gateway_status == "PAID"
    end

    attempt.update!(
      status: "failed",
      failure_reason: attempt.failure_reason.presence || "Payment attempt timed out with no confirmation from Cashfree",
      failed_at: Time.current
    )
  rescue StandardError => e
    Rails.logger.error("[CleanupStuckPaymentAttemptsJob] attempt #{attempt.id}: #{e.message}")
  end

  def fetch_gateway_status(attempt)
    CashfreeService.new.fetch_order(attempt.gateway_order_reference)["order_status"].to_s.upcase
  rescue StandardError => e
    Rails.logger.warn("[CleanupStuckPaymentAttemptsJob] could not verify attempt #{attempt.id} with Cashfree: #{e.message}")
    nil
  end
end
