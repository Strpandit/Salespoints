class SecurityAlertMailer < ApplicationMailer
  def failed_logins(super_admin_id, admin_id, attempts, ip_addresses)
    @recipient = AdminUser.find_by(id: super_admin_id)
    @admin = AdminUser.find_by(id: admin_id)
    return if @recipient&.email.blank? || @admin.blank?

    @attempts = attempts.to_i
    @ip_addresses = Array(ip_addresses)
    @window = SecurityAlertService::FAILED_LOGIN_WINDOW.inspect
    mail(to: @recipient.email, subject: "🚨 [SalesPoints] Security alert: #{@attempts} failed logins on #{@admin.email}")
  end
end
