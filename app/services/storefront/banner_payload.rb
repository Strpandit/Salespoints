module Storefront
  class BannerPayload
    include Rails.application.routes.url_helpers

    def initialize(base_url:)
      @base_url = base_url
    end

    def hero_slide(slide, admin: false)
      payload = {
        id: slide.id,
        badge: slide.badge,
        title: slide.title,
        highlight: slide.highlight,
        subtitle: slide.subtitle,
        discount_text: slide.discount_text,
        cta_label: slide.cta_label,
        link_url: slide.link_url,
        secondary_cta_label: slide.secondary_cta_label,
        secondary_link_url: slide.secondary_link_url,
        theme: slide.theme,
        position: slide.position,
        image_url: attachment_url(slide.image)
      }
      return payload unless admin

      payload.merge(
        is_active: slide.is_active,
        starts_at: slide.starts_at,
        ends_at: slide.ends_at,
        status: slide.display_status,
        created_at: slide.created_at,
        updated_at: slide.updated_at
      )
    end

    def flash_sale(sale, admin: false)
      items = admin ? sale.flash_sale_items : sale.displayable_items
      payload = {
        id: sale.id,
        title: sale.title,
        badge_text: sale.badge_text,
        subtitle: sale.subtitle,
        starts_at: sale.starts_at,
        ends_at: sale.ends_at,
        show_countdown: sale.show_countdown,
        items: items.map { |item| flash_sale_item(item) }
      }
      return payload unless admin

      payload.merge(
        is_active: sale.is_active,
        position: sale.position,
        status: sale.display_status,
        created_at: sale.created_at,
        updated_at: sale.updated_at
      )
    end

    def flash_sale_item(item)
      base = {
        id: item.id,
        item_type: item.item_type,
        item_id: item.item_id,
        label: item.label,
        position: item.position,
        available: item.displayable?
      }
      details = item_details(item.item)
      return base.merge(name: "Item no longer exists", available: false) if details.nil?

      base.merge(details)
    end

    # Normalised card data for a Product or DealerOffer (also used by the admin item picker).
    def item_details(record)
      case record
      when Product then product_details(record)
      when DealerOffer then offer_details(record)
      end
    end

    private

    def product_details(product)
      variants = product.product_variants.to_a
      variant = variants.select { |v| v.is_active && v.deleted_at.nil? }.min_by(&:id) || variants.min_by(&:id)
      price = (variant&.selling_price || product.try(:selling_price)).to_f
      mrp = (variant&.price || product.try(:price)).to_f
      discount = variant ? variant.calculate_discount_percentage.to_i : 0
      discount = (((mrp - price) / mrp) * 100).round if discount.zero? && mrp > price && mrp.positive?
      category_slug = product.category&.slug

      {
        name: product.name,
        subtitle: [ product.brand&.name, variant&.variant_sku ].compact.join(" · ").presence,
        image_url: attachment_url(product.ordered_media_attachments.first),
        price: price,
        mrp: mrp,
        discount_percent: discount,
        product_slug: product.slug,
        category_slug: category_slug,
        web_path: category_slug.present? ? "/#{category_slug}/#{product.slug}" : nil
      }
    end

    def offer_details(offer)
      price = offer.offer_price.to_f
      mrp = offer.product_variant&.price.to_f
      discount = mrp > price && mrp.positive? ? (((mrp - price) / mrp) * 100).round : 0

      {
        name: offer.display_title,
        subtitle: [ "Offer Mart", offer.seller_code ].compact.join(" · "),
        image_url: attachment_url(offer.media.first),
        price: price,
        mrp: mrp,
        discount_percent: discount,
        offer_slug: offer.slug.presence || offer.id.to_s,
        web_path: "/offer-mart/#{offer.slug.presence || offer.id}"
      }
    end

    def attachment_url(attachment)
      return nil if attachment.blank?
      return nil if attachment.respond_to?(:attached?) && !attachment.attached?

      rails_blob_url(attachment, host: @base_url)
    rescue StandardError
      nil
    end
  end
end
