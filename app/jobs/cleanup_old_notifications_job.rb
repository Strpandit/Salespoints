class CleanupOldNotificationsJob < ApplicationJob
  queue_as :cleanup

  RETENTION = 90.days

  def perform
    scope = Notification.where("created_at < ?", RETENTION.ago)

    scope = scope.where.not(id: B2bOrderOffer.where.not(notification_id: nil).select(:notification_id))
    scope = scope.where.not(id: OrderOffer.where.not(notification_id: nil).select(:notification_id))
    scope = scope.where.not(id: WhatsappWebhookEvent.where.not(notification_id: nil).select(:notification_id))

    scope.in_batches(of: 1000).delete_all
  end
end
