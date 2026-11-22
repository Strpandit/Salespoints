module OrderAlertLabels
  module_function

  def variant_label(variant)
    return nil if variant.blank?

    values = attribute_values(variant.try(:variant_attributes))
    return values.join(" / ") if values.any?

    variant.try(:variant_sku).presence
  end

  def color_label(item)
    return nil if item.blank?

    item.try(:product_variant_color)&.color_name.presence || item.try(:ad_hoc_color).presence
  end

  def pincode(address = nil, text = nil)
    code = address_value(address, "postal_code").presence || address_value(address, "pincode").presence
    code = code.to_s.strip
    return code if code.match?(/\A\d{6}\z/)

    text.to_s.scan(/\b\d{6}\b/).last
  end

  def wholesaler_request_details(order, item)
    post = item.try(:wholesaler_post)
    variant = post&.dealer_product&.product_variant || item.try(:product_variant)
    product = variant&.product || post&.dealer_product&.product
    buyer = order.buyer_dealer
    seller = order.seller_dealer
    business_address = buyer&.dealer_profile&.business_address.to_s.strip

    buyer_location = buyer&.dealer_location
    seller_location = seller&.dealer_location
    distance =
      if buyer_location&.latitude.present? && buyer_location&.longitude.present? &&
         seller_location&.latitude.present? && seller_location&.longitude.present?
        DealerLocation.distance_km(
          buyer_location.latitude.to_f, buyer_location.longitude.to_f,
          seller_location.latitude.to_f, seller_location.longitude.to_f
        ).round(1)
      end

    {
      item_name: product&.name.presence || post&.title.presence || "Product",
      variant_name: variant_label(variant) || post&.modal_no.presence,
      color_name: color_label(item) || post&.ad_hoc_color.presence,
      pincode: pincode(order.shipping_address, business_address),
      distance_km: distance,
      delivery_area: delivery_area(business_address)
    }.compact
  rescue StandardError => e
    Rails.logger.warn("[OrderAlertLabels] wholesaler details failed for #{order.class.name}##{order.try(:id)}: #{e.message}")
    {}
  end

  def delivery_area(full_address)
    cleaned = full_address.to_s.gsub(/\b\d{6}\b/, "").gsub(/\b(India|Bharat)\b/i, "").gsub(/,\s*,+/, ",").strip.delete_prefix(",").delete_suffix(",").strip
    return nil if cleaned.blank?

    parts = cleaned.split(",").map(&:strip).reject(&:blank?)
    parts.any? ? parts.last(3).join(", ") : cleaned
  end

  def address_value(address, key)
    return nil if address.blank?
    return address[key] || address[key.to_sym] if address.respond_to?(:[]) && !address.is_a?(String)

    nil
  rescue StandardError
    nil
  end

  def attribute_values(raw)
    data = raw
    data = JSON.parse(data) if data.is_a?(String) && data.present?
    entries =
      case data
      when Array then data
      when Hash then data.map { |key, value| { "key" => key, "value" => value } }
      else []
      end

    entries.filter_map do |entry|
      value = entry.respond_to?(:[]) && !entry.is_a?(String) ? (entry["value"] || entry[:value]) : entry
      value.to_s.strip.presence
    end
  rescue StandardError
    []
  end
end
