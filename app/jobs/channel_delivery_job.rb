class ChannelDeliveryJob < ApplicationJob
  queue_as :whatsapp_meta

  retry_on Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, attempts: 3, wait: :exponentially_longer

  def perform(notification_id)
    notification = Notification.find_by(id: notification_id)
    return unless notification

    channels = notification.delivery_channels
    return unless channels["whatsapp"] == true || channels["whatsapp"] == "true"

    receiver = notification.receiver
    return unless receiver.present?

    phone = receiver.try(:phone).presence || notification.payload&.dig("phone")
    return if phone.blank?

    country_code = receiver.try(:country_code).presence || notification.payload&.dig("country_code") || "+91"
    formatted_to = "#{country_code}#{phone}".gsub(/\s+/, "")

    service = MetaWhatsappCloudService.new
    return unless service.configured?

    body = "#{notification.title}\n\n#{notification.body}"
    service.send_text_message(to: formatted_to, body: body)
  rescue StandardError => e
    Rails.logger.error("ChannelDeliveryJob failed for Notification ##{notification_id}: #{e.message}")
  end
end
