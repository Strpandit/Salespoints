class GenerateReportJob < ApplicationJob
  queue_as :pdf_reports

  retry_on StandardError, attempts: 3, wait: :exponentially_longer

  def perform(report_key:, format: "xlsx", filters: {}, user_type: "AdminUser", user_id: nil, recipient_email: nil)
    user = user_type.constantize.find_by(id: user_id) if user_id.present?
    scope = user_type == "AdminUser" ? :admin : :vendor

    exporter = Reports::ExporterFactory.for(report_key, filters: filters, current_user: user, scope: scope)
    report_data = exporter.generate

    formatted_data = case format.to_s.downcase
                     when "xlsx" then Reports::Formatters::XlsxFormatter.render(report_data)
                     when "pdf"  then Reports::Formatters::PdfFormatter.render(report_data)
                     when "json" then Reports::Formatters::JsonFormatter.render(report_data)
                     else             Reports::Formatters::CsvFormatter.render(report_data)
                     end

    ReportAuditLog.create!(
      user: user,
      report_key: report_key,
      format: format,
      applied_filters: filters.is_a?(Hash) ? filters : {},
      row_count: (report_data[:rows] || []).size,
      downloaded_at: Time.current
    ) if defined?(ReportAuditLog)

    if recipient_email.present? && user.present?
      filename = "#{report_key}_#{Time.current.strftime('%Y%m%d_%H%M%S')}.#{format}"
      AdminNotificationMailer.general_notification(
        email: recipient_email,
        subject: "Your requested report #{report_key.humanize} is ready",
        body: "Please find attached your requested #{report_key.humanize} report.",
        attachments: { filename => formatted_data }
      ).deliver_later(queue: :notifications_mail) if defined?(AdminNotificationMailer)
    end

    formatted_data
  end
end
