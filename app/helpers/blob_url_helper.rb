module BlobUrlHelper
  def self.blob_url(file, host: nil)
    return nil if file.blank?

    blob = file.respond_to?(:blob) && file.blob.present? ? file.blob : file
    return nil unless blob.respond_to?(:filename)

    public_cdn = ENV["R2_PUBLIC_URL"].presence || ENV["STORAGE_PUBLIC_HOST"].presence || ENV["CLOUDFLARE_R2_PUBLIC_URL"].presence
    if public_cdn.present? && blob.respond_to?(:key) && blob.key.present?
      return "#{public_cdn.chomp('/')}/#{blob.key}"
    end

    effective_host = host || Rails.application.config.active_storage.default_url_options&.dig(:host)
    effective_host = effective_host.to_s.sub(%r{\Ahttp://}, "https://") if effective_host.present?

    url = Rails.application.routes.url_helpers.rails_blob_url(blob, host: effective_host, protocol: "https")
    url = url.sub(%r{\Ahttp://}, "https://") if url.present?
    url
  rescue => e
    Rails.logger.warn("[BlobUrlHelper] Error generating blob URL: #{e.message}")
    nil
  end

  def self.attachment_payload(file, host: nil)
    return nil if file.blank?

    blob = file.respond_to?(:blob) && file.blob.present? ? file.blob : file
    return nil unless blob.respond_to?(:filename)

    {
      id: blob.id,
      url: blob_url(blob, host: host),
      filename: blob.filename.to_s,
      content_type: blob.content_type.to_s
    }
  rescue => e
    nil
  end
end
