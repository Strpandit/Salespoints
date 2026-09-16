class CleanupOldWebhookEventsJob < ApplicationJob
  queue_as :cleanup

  RETENTION = 90.days

  def perform
    PaymentGatewayWebhookEvent.where("received_at < ?", RETENTION.ago).in_batches(of: 1000).delete_all
  end
end
