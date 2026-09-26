class DealerProductSerializer < ApplicationSerializer
  attributes :stock_quantity, :color_stocks, :is_active, :approve_status, :sell_in_b2b, :sell_in_b2c, :created_at, :updated_at, :distance_km,
             :media, :consumer_discount_percentage,
             :dealer_discount_percentage, :from_wholesaler, :wholesaler_post_id, :hsn_code

  belongs_to :dealer
  belongs_to :product
  belongs_to :product_variant

  def distance_km
    object.respond_to?(:distance_km) ? object.distance_km : nil
  end

  def from_wholesaler
    object.respond_to?(:from_wholesaler) ? object.from_wholesaler : false
  end

  def wholesaler_post_id
    object.respond_to?(:wholesaler_post_id) ? object.wholesaler_post_id : nil
  end

  def consumer_discount_percentage
    object.product_variant&.calculate_discount_percentage(:account)
  end

  def dealer_discount_percentage
    object.product_variant&.calculate_discount_percentage(:dealer)
  end
  
  def media
    object.display_media_attachments.map { |file| file_payload(file) }
  end

  def hsn_code
    object.effective_hsn_code
  end

  private

  def file_payload(file)
    host = options[:base_url] || Rails.application.config.active_storage.default_url_options&.dig(:host)
    payload = BlobUrlHelper.attachment_payload(file, host: host) || {}
    payload[:is_primary] = object.display_primary_blob_id == (file.respond_to?(:blob_id) ? file.blob_id : file.id)
    payload
  end
end
