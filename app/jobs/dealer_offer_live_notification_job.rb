class DealerOfferLiveNotificationJob < ApplicationJob
  queue_as :notifications

  def perform(offer_id)
    offer = DealerOffer.find_by(id: offer_id)
    return unless offer && offer.approve_status == "approved"

    pincodes = Array(offer.pincodes).map { |code| code.to_s.strip }.reject(&:blank?).uniq
    return if pincodes.empty?

    nearby = Address.where(postal_code: pincodes).where.not(account_id: nil).select(:account_id)
    Account.where(id: nearby).where.not(status: %w[banned inactive]).find_each do |account|
      next if Notification.exists?(receiver: account, notifiable: offer, notification_type: "offer_mart_deal_active")

      PushEventsHub.customer_offermart_offer_live(account, offer)
    end
  end
end
