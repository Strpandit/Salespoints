# Raises an alert to super admins when an admin account sees repeated failed logins
# (wrong password or wrong OTP), which usually means someone is guessing credentials.
class SecurityAlertService
  FAILED_LOGIN_THRESHOLD = 5
  FAILED_LOGIN_WINDOW = 15.minutes
  ALERT_COOLDOWN = 30.minutes
  ALERT_KIND = "security_failed_logins".freeze

  class << self
    def check_failed_logins!(admin, request: nil)
      return if admin.blank?

      since = FAILED_LOGIN_WINDOW.ago
      failures = ActivityLog.where(actor_type: admin.class.name, actor_id: admin.id, action: "login_failed")
                            .where("created_at >= ?", since)
      count = failures.count
      return if count < FAILED_LOGIN_THRESHOLD
      return if recently_alerted?(admin)

      ips = failures.where.not(ip_address: nil).distinct.pluck(:ip_address).first(5)
      message = "#{count} failed login attempts on admin account #{admin.full_name.presence || admin.email} in the last " \
                "#{FAILED_LOGIN_WINDOW.inspect}#{ips.any? ? " from IP #{ips.join(', ')}" : ''}."

      recipients.each do |super_admin|
        NotificationService.deliver(
          recipient: super_admin,
          actor: admin,
          notifiable: admin,
          kind: ALERT_KIND,
          title: "Security alert: repeated failed logins",
          message: message,
          payload: { admin_user_id: admin.id, attempts: count, ip_addresses: ips, path: "/admin/activity-logs", url: "/admin/activity-logs" },
          delivery_channels: { push: true, in_app: true, email: true }
        )
        SecurityAlertMailer.failed_logins(super_admin.id, admin.id, count, ips).deliver_later if super_admin.email.present?
      end

      ActivityLogger.log(
        actor: admin,
        action: "security_alert_raised",
        category: "security",
        description: "Security alert sent to super admins: #{count} failed logins in #{FAILED_LOGIN_WINDOW.inspect}",
        metadata: { attempts: count, ip_addresses: ips },
        request: request
      )
    rescue StandardError => e
      Rails.logger.error("[SecurityAlertService] #{e.class}: #{e.message}")
    end

    private

    def recently_alerted?(admin)
      Notification.where(notification_type: ALERT_KIND, notifiable: admin)
                  .where("created_at >= ?", ALERT_COOLDOWN.ago)
                  .exists?
    end

    def recipients
      AdminUser.where(is_super_admin: true, deleted_at: nil, status: "active")
    end
  end
end
