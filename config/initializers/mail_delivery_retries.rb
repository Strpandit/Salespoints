Rails.application.config.to_prepare do
  ActionMailer::MailDeliveryJob.retry_on(
    Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, Errno::ECONNREFUSED, Errno::ETIMEDOUT,
    SocketError, EOFError, Net::SMTPServerBusy, Net::SMTPUnknownError,
    attempts: 5, wait: :polynomially_longer
  )
  ActionMailer::MailDeliveryJob.discard_on(ActiveJob::DeserializationError)
end
