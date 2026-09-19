class OrderItemSerializer < ApplicationSerializer
  attributes :quantity, :unit_price, :taxable_amount, :gst_percentage, 
            :gst_amount, :total_price, :product_name, :product_name_with_variant,
            :variant_sku, :product_id, :variant_id, :product_media, :variant_media,
            :color, :image_url

  def image_url
    pvc = object.product_variant_color
    color_blob = pvc&.ordered_media_attachments&.first&.blob
    if color_blob
      payload = file_payload(color_blob)
      return payload[:url] if payload
    end

    pv = object.product_variant
    dp = object.dealer_product
    blob = pv&.product&.media&.first&.blob || dp&.product&.media&.first&.blob
    return nil unless blob
    payload = file_payload(blob)
    payload ? payload[:url] : nil
  rescue => e
    nil
  end

  def pricing
    @pricing ||= begin
      if object.product_variant.present? && object.product_variant.product.present?
        Pricing::PriceCalculator.new(
          variant: object.product_variant,
          quantity: object.quantity,
          user_type: object.order&.buyer_type == "Dealer" ? :dealer : :account
        ).call
      else
        {}
      end
    rescue StandardError => e
      Rails.logger.warn("OrderItemSerializer pricing calculation error for item #{object.id}: #{e.message}")
      {}
    end
  end

  def unit_price
    pricing[:unit_price] || object.read_attribute(:unit_price).to_f
  end

  def taxable_amount
    pricing[:taxable_amount] || object.read_attribute(:taxable_amount).to_f
  end

  def gst_percentage
    pricing[:gst_percentage] || object.read_attribute(:gst_percentage).to_f
  end

  def gst_amount
    pricing[:gst_amount] || object.read_attribute(:gst_amount).to_f
  end

  def total_price
    pricing[:total] || object.read_attribute(:total_price).to_f
  end

  def product_name
    object.product_name
  end

  def product_name_with_variant
    object.product_name_with_variant
  end

  def variant_sku
    object.product_variant&.variant_sku
  end

  def product_id
    object.product_variant&.product_id
  end

  def variant_id
    object.product_variant_id
  end

  def product_media
    object.product_variant&.product&.media&.map { |file| file_payload(file) } || []
  end

  def variant_media
    object.product_variant&.media&.map { |file| file_payload(file) } || []
  end

  def color
    if object.product_variant_color.present?
      object.product_variant_color.color_name
    elsif object.ad_hoc_color.present?
      object.ad_hoc_color
    else
      "Standard"
    end
  end

  private

  def file_payload(file)
    host = options[:base_url] || Rails.application.config.active_storage.default_url_options&.dig(:host)
    {
      id: file.id,
      url: Rails.application.routes.url_helpers.rails_blob_url(file, host: host),
      filename: file.filename.to_s,
      content_type: file.content_type.to_s
    }
  end
end
