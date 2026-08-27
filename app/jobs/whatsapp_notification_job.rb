class WhatsappNotificationJob < ApplicationJob
  queue_as :whatsapp_meta

  retry_on Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, attempts: 3, wait: :exponentially_longer

  def perform(method_name, *args, **kwargs)
    service = MetaWhatsappCloudService.new
    if kwargs.present?
      service.public_send(method_name, *args, **kwargs)
    else
      service.public_send(method_name, *args)
    end
  end
end
