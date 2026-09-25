class DealerOfferExpiryReminderJob < ApplicationJob
  queue_as :cleanup

  ONE_DAY_WINDOW = 24.hours
  ONE_HOUR_WINDOW = 1.hour

  def perform
    DealerOffer.approved.where(is_active: true).includes(:dealer).find_each do |offer|
      next unless offer.started?

      visible_until = offer.visible_until
      next if visible_until.blank?

      remaining = visible_until - Time.current
      next if remaining <= 0

      maybe_send_reminder!(offer, 24) if remaining <= ONE_DAY_WINDOW && remaining > ONE_HOUR_WINDOW
      maybe_send_reminder!(offer, 1) if remaining <= ONE_HOUR_WINDOW
    end
  end

  private

  def maybe_send_reminder!(offer, hours_before)
    return if DealerOfferNotificationService.expiry_reminder_already_sent?(offer, hours_before)

    DealerOfferNotificationService.notify_expiry_reminder!(offer, hours_before)
  rescue StandardError => e
    Rails.logger.error("[DealerOfferExpiryReminderJob] failed for offer ##{offer.id} (#{hours_before}h): #{e.message}")
  end
end
