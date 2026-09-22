class WholesalerPostMailer < ApplicationMailer
  def admin_new_post(post_id, admin_email)
    @post = load_post(post_id)
    return unless @post

    @dealer = @post.dealer
    mail(to: admin_email, subject: "🆕 [SalesPoints] New Wholesaler Post Awaiting Approval - #{@post.title}")
  end

  def post_approved(post_id)
    @post = load_post(post_id)
    return unless @post

    @dealer = @post.dealer
    return if @dealer&.email.blank?

    mail(to: @dealer.email, subject: "✅ Your Wholesaler Post Has Been Approved - #{@post.title}")
  end

  def post_rejected(post_id)
    @post = load_post(post_id)
    return unless @post

    @dealer = @post.dealer
    return if @dealer&.email.blank?

    mail(to: @dealer.email, subject: "Your Wholesaler Post Needs Attention - #{@post.title}")
  end

  def post_live_for_dealer(post_id, dealer_id)
    @post = load_post(post_id)
    return unless @post

    @dealer = Dealer.find_by(id: dealer_id)
    return if @dealer&.email.blank?

    mail(to: @dealer.email, subject: "📢 New Wholesaler Post Live - #{@post.title}")
  end

  def expiry_reminder(post_id, hours_before)
    @post = load_post(post_id)
    return unless @post

    @dealer = @post.dealer
    @hours_before = hours_before.to_i
    return if @dealer&.email.blank?

    time_label = @hours_before >= 24 ? "24 Hours" : "1 Hour"
    mail(to: @dealer.email, subject: "⏰ Your Wholesaler Post Expires in #{time_label} - #{@post.title}")
  end

  private

  def load_post(post_id)
    WholesalerPost.includes(:dealer, :reviewed_by_admin).find_by(id: post_id)
  end
end
