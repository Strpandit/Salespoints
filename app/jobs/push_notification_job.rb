class PushNotificationJob < ApplicationJob
  queue_as :notifications_mail

  MAX_ATTEMPTS = 5
  RETRY_DELAY = 30.seconds

  retry_on ActiveRecord::ConnectionNotEstablished, ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout,
           wait: 15.seconds, attempts: 5

  def perform(app_notification_id, tokens = nil, attempt = 1)
    notification = Notification.find_by(id: app_notification_id)
    return unless notification

    failed_tokens = PushNotificationService.new.deliver(notification, tokens: tokens)
    return if failed_tokens.blank?

    if attempt >= MAX_ATTEMPTS
      Rails.logger.error("[PushNotificationJob] giving up on notification=#{app_notification_id}: #{failed_tokens.size} device(s) not reached after #{attempt} attempts")
      return
    end

    self.class.set(wait: RETRY_DELAY * attempt).perform_later(app_notification_id, failed_tokens, attempt + 1)
  end
end
