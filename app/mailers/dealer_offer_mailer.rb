class DealerOfferMailer < ApplicationMailer
  def expiry_reminder(offer_id, hours_before)
    @offer = DealerOffer.includes(:dealer).find_by(id: offer_id)
    return unless @offer

    @dealer = @offer.dealer
    @hours_before = hours_before.to_i
    return if @dealer&.email.blank?

    time_label = @hours_before >= 24 ? "24 Hours" : "1 Hour"
    mail(to: @dealer.email, subject: "⏰ Your Offer Mart Offer Expires in #{time_label} - #{@offer.display_title}")
  end
end
