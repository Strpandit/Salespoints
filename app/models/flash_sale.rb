class FlashSale < ApplicationRecord
  MAX_ITEMS = 8

  has_many :flash_sale_items, -> { order(:position, :id) }, dependent: :destroy, inverse_of: :flash_sale

  validates :title, presence: true, length: { maximum: 80 }
  validates :badge_text, length: { maximum: 40 }
  validates :subtitle, length: { maximum: 200 }
  validates :starts_at, :ends_at, presence: true
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :window_valid
  validate :items_limit

  scope :ordered, -> { order(:position, :ends_at, :id) }
  scope :visible, lambda {
    now = Time.current
    where(is_active: true).where("flash_sales.starts_at <= ? AND flash_sales.ends_at > ?", now, now)
  }

  def self.current
    visible.ordered.includes(flash_sale_items: :item).detect { |sale| sale.displayable_items.any? }
  end

  def displayable_items
    flash_sale_items.select(&:displayable?)
  end

  def display_status
    return "hidden" unless is_active?
    return "scheduled" if starts_at.present? && starts_at > Time.current
    return "ended" if ends_at.present? && ends_at <= Time.current
    return "no_items" if displayable_items.empty?

    "live"
  end

  private

  def window_valid
    return if starts_at.blank? || ends_at.blank?

    errors.add(:ends_at, "must be after the start time") if ends_at <= starts_at
  end

  def items_limit
    count = flash_sale_items.reject(&:marked_for_destruction?).size
    errors.add(:base, "A flash sale can have at most #{MAX_ITEMS} items") if count > MAX_ITEMS
  end
end
