class ProductVariant < ApplicationRecord
  belongs_to :product

  has_many :dealer_products
  has_many :order_items

  validates :variant_sku, presence: true
  validates :selling_price, :dealer_selling_price, presence: true, numericality: true

  scope :active, -> { where(is_active: true, deleted_at: nil) }

  def effective_hsn_code
    hsn_code.presence || product&.hsn_code
  end

  def unit_price_for(user_type)
    case user_type.to_sym
    when :dealer
      dealer_selling_price.presence ||
        selling_price.presence ||
        dealer_price.presence ||
        price
    else
      selling_price.presence ||
        price
    end.to_d
  end

  def display_media_attachments
    product ? product.ordered_media_attachments.map(&:blob) : []
  end

  def display_primary_blob_id
    product&.primary_media_blob_id
  end

  def ordered_media_attachments
    product ? product.ordered_media_attachments : []
  end

  def primary_media_blob_id
    product&.primary_media_blob_id
  end

  def media
    product ? product.media : nil
  end

  def calculate_discount_percentage(user_type = :account)
    original_price, selling_price_value =
      if user_type.to_sym == :dealer
        [dealer_price, dealer_selling_price]
      else
        [price, selling_price]
      end

    return 0 if original_price.blank? ||
                selling_price_value.blank? ||
                original_price <= selling_price_value

    (((original_price.to_d - selling_price_value.to_d) / original_price.to_d) * 100).round
  end

  def deleted?
    !!deleted_at
  end

  def sellable?
    is_active && !deleted?
  end
end

