class WholesalerPostNotificationService
  class << self
    def notify_created!(post)
      admins = admin_recipients
      admins.each do |admin|
        NotificationService.deliver(
          recipient: admin,
          actor: post.dealer,
          notifiable: post,
          kind: "wholesaler_post_created",
          title: "New Wholesaler Post Awaiting Approval",
          message: "#{dealer_label(post.dealer)} submitted a new wholesaler post: #{post.title}",
          payload: post_payload(post),
          delivery_channels: { push: true, in_app: true, email: true }
        )
        WholesalerPostMailer.admin_new_post(post.id, admin.email).deliver_later if admin.email.present?
      end
    rescue StandardError => e
      Rails.logger.error("[WholesalerPostNotificationService] notify_created! failed: #{e.message}")
    end

    def notify_approved!(post)
      dealer = post.dealer
      return unless dealer

      NotificationService.deliver(
        recipient: dealer,
        actor: post.reviewed_by_admin,
        notifiable: post,
        kind: "wholesaler_post_approved",
        title: "Wholesaler Post Approved",
        message: "Your wholesaler post \"#{post.title}\" has been approved and is now live.",
        payload: post_payload(post),
        delivery_channels: { push: true, in_app: true, email: true }
      )
      WholesalerPostMailer.post_approved(post.id).deliver_later if dealer.email.present?
    rescue StandardError => e
      Rails.logger.error("[WholesalerPostNotificationService] notify_approved! failed: #{e.message}")
    end

    def notify_rejected!(post)
      dealer = post.dealer
      return unless dealer

      NotificationService.deliver(
        recipient: dealer,
        actor: post.reviewed_by_admin,
        notifiable: post,
        kind: "wholesaler_post_rejected",
        title: "Wholesaler Post Rejected",
        message: "Your wholesaler post \"#{post.title}\" was rejected. #{post.rejection_reason.presence}".strip,
        payload: post_payload(post),
        delivery_channels: { push: true, in_app: true, email: true }
      )
      WholesalerPostMailer.post_rejected(post.id).deliver_later if dealer.email.present?
    rescue StandardError => e
      Rails.logger.error("[WholesalerPostNotificationService] notify_rejected! failed: #{e.message}")
    end

    def notify_matching_dealers_live!(post)
      target_pincodes = Array(post.pincodes).map(&:to_s).reject(&:blank?)
      return if target_pincodes.empty?

      dealers = Dealer.where(status: "active").where(deleted_at: nil).where.not(id: post.dealer_id)
      dealers = dealers.where(pincode: target_pincodes)

      price_text = post.price.present? ? "at ₹#{post.price.to_f.round(2)}" : ""
      title = "📢 New Wholesaler Post Live!"
      message = "New Wholesaler Post is Live now: #{post.title} #{price_text}. Check it out on your Wholesaler Feed!"

      dealers.find_each do |target_dealer|
        NotificationService.deliver(
          recipient: target_dealer,
          actor: post.dealer,
          notifiable: post,
          kind: "new_wholesaler_post",
          title: title,
          message: message,
          visible_in_app: true,
          delivery_channels: { push: true, in_app: true, email: true, whatsapp: false, sms: false },
          payload: {
            post_id: post.id,
            wholesaler_post_id: post.id,
            title: post.title,
            price: post.price.to_f,
            seller_code: post.dealer&.dealer_code,
            path: "/dealer/wholesaler?post_id=#{post.id}",
            url: "/dealer/wholesaler?post_id=#{post.id}",
            link: "/dealer/wholesaler?post_id=#{post.id}",
            route: "DealerWholesalerFeed",
            params: { post_id: post.id }
          }
        )
        WholesalerPostMailer.post_live_for_dealer(post.id, target_dealer.id).deliver_later if target_dealer.email.present?
      end
    rescue StandardError => e
      Rails.logger.error("[WholesalerPostNotificationService] notify_matching_dealers_live! failed: #{e.message}")
    end

    def expiry_reminder_kind(hours_before)
      hours_before.to_i >= 24 ? "wholesaler_post_expiring_1day" : "wholesaler_post_expiring_1hour"
    end

    def expiry_reminder_already_sent?(post, hours_before)
      cycle_start = post.reuploaded_at.presence || post.created_at
      Notification.where(notifiable: post, notification_type: expiry_reminder_kind(hours_before))
                  .where("created_at >= ?", cycle_start)
                  .exists?
    end

    def notify_expiry_reminder!(post, hours_before)
      dealer = post.dealer
      return unless dealer

      time_label = hours_before.to_i >= 24 ? "24 hours" : "1 hour"
      NotificationService.deliver(
        recipient: dealer,
        actor: dealer,
        notifiable: post,
        kind: expiry_reminder_kind(hours_before),
        title: "Wholesaler Post Expiring Soon",
        message: "Your wholesaler post \"#{post.title}\" expires in #{time_label}. Re-upload it to stay visible.",
        payload: post_payload(post),
        delivery_channels: { push: true, in_app: true, email: true }
      )
      WholesalerPostMailer.expiry_reminder(post.id, hours_before).deliver_later if dealer.email.present?
    rescue StandardError => e
      Rails.logger.error("[WholesalerPostNotificationService] notify_expiry_reminder! failed: #{e.message}")
    end

    private

    def admin_recipients
      AdminUser.where(is_super_admin: true).where(status: "active").where.not(email: [nil, ""])
    end

    def dealer_label(dealer)
      return "A dealer" unless dealer

      dealer.dealer_profile&.business_name.presence || dealer.full_name.presence || dealer.dealer_code.presence || "A dealer"
    end

    def post_payload(post)
      {
        post_id: post.id,
        title: post.title,
        price: post.price&.to_f,
        stock_quantity: post.stock_quantity,
        approve_status: post.approve_status
      }.compact
    end
  end
end
