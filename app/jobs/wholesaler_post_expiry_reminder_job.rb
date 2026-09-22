class WholesalerPostExpiryReminderJob < ApplicationJob
  queue_as :cleanup

  ONE_DAY_WINDOW = 24.hours
  ONE_HOUR_WINDOW = 1.hour

  def perform
    WholesalerPost.approved_and_live.find_each do |post|
      remaining = remaining_time(post)
      next if remaining.nil? || remaining <= 0

      maybe_send_reminder!(post, 24) if remaining <= ONE_DAY_WINDOW
      maybe_send_reminder!(post, 1) if remaining <= ONE_HOUR_WINDOW
    end
  end

  private

  def remaining_time(post)
    visible_until = post.visible_until
    return nil if visible_until.blank?

    visible_until - Time.current
  end

  def maybe_send_reminder!(post, hours_before)
    return if WholesalerPostNotificationService.expiry_reminder_already_sent?(post, hours_before)

    WholesalerPostNotificationService.notify_expiry_reminder!(post, hours_before)
  rescue StandardError => e
    Rails.logger.error("[WholesalerPostExpiryReminderJob] failed for post ##{post.id} (#{hours_before}h): #{e.message}")
  end
end
