class FlashSaleItem < ApplicationRecord
  ITEM_TYPES = %w[Product DealerOffer].freeze

  belongs_to :flash_sale, inverse_of: :flash_sale_items
  belongs_to :item, polymorphic: true

  validates :item_type, inclusion: { in: ITEM_TYPES }
  validates :item_id, uniqueness: { scope: [ :flash_sale_id, :item_type ], message: "is already added to this flash sale" }
  validates :label, length: { maximum: 20 }

  def displayable?
    self.class.sellable?(item)
  end

  def self.sellable?(record)
    case record
    when Product
      record.is_active? && record.deleted_at.nil? && record.category.present? &&
        record.product_variants.any? { |v| v.is_active && v.deleted_at.nil? && v.selling_price.to_f.positive? }
    when DealerOffer
      record.live?
    else
      false
    end
  end
end
