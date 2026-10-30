class PushNotificationJob < ApplicationJob
  queue_as :notifications_mail

  MAX_ATTEMPTS = 3
  RETRY_DELAY = 30.seconds

  def perform(app_notification_id, tokens = nil, attempt = 1)
    notification = Notification.find_by(id: app_notification_id)
    return unless notification

    failed_tokens = PushNotificationService.new.deliver(notification, tokens: tokens)
    return if failed_tokens.blank? || attempt >= MAX_ATTEMPTS

    self.class.set(wait: RETRY_DELAY * attempt).perform_later(app_notification_id, failed_tokens, attempt + 1)
  end
end
