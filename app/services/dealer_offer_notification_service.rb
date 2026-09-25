class DealerOfferNotificationService
  class << self
    def expiry_reminder_kind(hours_before)
      hours_before.to_i >= 24 ? "dealer_offer_expiring_1day" : "dealer_offer_expiring_1hour"
    end

    def expiry_reminder_already_sent?(offer, hours_before)
      cycle_start = offer.reuploaded_at.presence || offer.offer_starts_at.presence || offer.created_at
      Notification.where(notifiable: offer, notification_type: expiry_reminder_kind(hours_before))
                  .where("created_at >= ?", cycle_start)
                  .exists?
    end

    def notify_expiry_reminder!(offer, hours_before)
      dealer = offer.dealer
      return unless dealer

      time_label = hours_before.to_i >= 24 ? "24 hours" : "1 hour"
      NotificationService.deliver(
        recipient: dealer,
        actor: dealer,
        notifiable: offer,
        kind: expiry_reminder_kind(hours_before),
        title: "Offer Mart Offer Expiring Soon",
        message: "Your Offer Mart offer \"#{offer.display_title}\" expires in #{time_label}. Re-upload it after expiry to keep it live.",
        payload: offer_payload(offer),
        delivery_channels: { push: true, in_app: true, email: true }
      )
      DealerOfferMailer.expiry_reminder(offer.id, hours_before).deliver_later if dealer.email.present?
    rescue StandardError => e
      Rails.logger.error("[DealerOfferNotificationService] notify_expiry_reminder! failed: #{e.message}")
    end

    private

    def offer_payload(offer)
      {
        offer_id: offer.id,
        dealer_offer_id: offer.id,
        title: offer.display_title,
        offer_price: offer.offer_price&.to_f,
        visible_until: offer.visible_until&.iso8601,
        live_days: offer.live_days,
        path: "/dealer/offers",
        url: "/dealer/offers",
        route: "DealerOffers"
      }.compact
    end
  end
end
