class DealerOffer < ApplicationRecord
  include AttachableMediaValidations

  belongs_to :dealer
  belongs_to :dealer_product
  belongs_to :product
  belongs_to :product_variant
  belongs_to :reviewed_by_admin, class_name: "AdminUser", optional: true

  has_many :orders, dependent: :nullify
  has_many_attached :media

  APPROVE_STATUSES = %w[pending approved rejected].freeze

  SCHEME_CATEGORIES = %w[
    special_price
    flash_sale
    clearance_sale
    old_stock_offer
    activated_phone_offer
    open_box_offer
    pre_owned_used_phone
    refurbished_phone
    exchange_offer
    bank_offer
    instant_discount
    coupon_offer
    bundle_offer
    free_accessory_offer
    buy_with_accessory
    festival_offer
    weekend_offer
    limited_stock_offer
    launch_model_upgrade_offer
    seller_special_offer
  ].freeze

  PRODUCT_CONDITIONS = %w[new activated open_box pre_owned refurbished].freeze

  DEFAULT_TAX_RATE = 18

  validates :scheme_category, inclusion: { in: SCHEME_CATEGORIES }
  validates :product_condition, inclusion: { in: PRODUCT_CONDITIONS }
  validates :approve_status, inclusion: { in: APPROVE_STATUSES }
  validates :slug, presence: true, uniqueness: true
  validates :offer_price,
            numericality: { greater_than_or_equal_to: 0 }
  validates :available_quantity, :sold_quantity,
            numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validate :offer_window_valid
  validate :media_files_valid
  validate :validate_pincodes_format

  before_validation :auto_assign_dealer_defaults, on: :create
  before_validation :set_slug, on: [ :create, :update ]

  scope :approved, -> { where(approve_status: "approved") }
  scope :visible_to_marketplace, -> {
    now = Time.current
    joins(:dealer)
      .where(dealers: { deleted_at: nil, status: "active" })
      .where(approve_status: "approved", is_active: true)
      .where("dealer_offers.available_quantity > dealer_offers.sold_quantity")
      .where("dealer_offers.offer_starts_at IS NULL OR dealer_offers.offer_starts_at <= ?", now)
      .where("dealer_offers.offer_ends_at IS NULL OR dealer_offers.offer_ends_at >= ?", now)
      .where("(dealer_offers.reuploaded_at >= ?) OR (dealer_offers.reuploaded_at IS NULL AND (dealer_offers.offer_starts_at >= ? OR dealer_offers.created_at >= ?))", 7.days.ago, 7.days.ago, 7.days.ago)
  }
  scope :by_pincode, ->(pincode) { where("? = ANY(pincodes)", pincode.to_s) }

  def to_param
    slug.presence || id.to_s
  end

  def display_title
    device_model.presence || product&.name || "Dealer Offer"
  end

  def remaining_quantity
    [ available_quantity.to_i - sold_quantity.to_i, 0 ].max
  end

  def visible_until
    base_date = reuploaded_at.presence || offer_starts_at.presence || created_at
    return offer_ends_at if offer_ends_at.present?
    base_date&.+(7.days)
  end

  def expired?
    (visible_until.present? && visible_until <= Time.current) ||
      (offer_ends_at.present? && offer_ends_at <= Time.current)
  end
  alias_method :is_expired?, :expired?

  def can_reupload?
    approve_status == "approved" && expired?
  end

  def reupload!
    return false unless can_reupload?

    update!(
      approve_status: "pending",
      reviewed_at: nil,
      rejection_reason: nil,
      reviewed_by_admin: nil,
      updated_at: Time.current,
      reuploaded_at: Time.current,
      offer_starts_at: Time.current,
      offer_ends_at: Time.current + 7.days
    )
  end

  def started?
    offer_starts_at.blank? || offer_starts_at <= Time.current
  end

  def live?
    approve_status == "approved" &&
      is_active? &&
      started? &&
      !expired? &&
      remaining_quantity.positive? &&
      dealer&.status == "active" &&
      dealer.deleted_at.nil?
  end

  def effective_tax_rate
    return tax_rate.to_d if tax_rate.present?
    return product.tax_rate.to_d if product&.tax_rate.present?

    (ENV["OFFER_MART_DEFAULT_TAX_RATE"].presence || DEFAULT_TAX_RATE).to_d
  end

  def effective_hsn_code
    product_variant&.effective_hsn_code || product&.hsn_code
  end

  def deduct_quantity!(qty)
    qty = qty.to_i
    raise ArgumentError, "Quantity must be positive" unless qty.positive?

    with_lock do
      raise StandardError, "Insufficient stock for this offer" if remaining_quantity < qty

      increment!(:sold_quantity, qty)

      if dealer_product.present?
        begin
          dealer_product.with_lock do
            if dealer_product.stock_quantity.to_i >= qty
              dealer_product.update!(stock_quantity: dealer_product.stock_quantity.to_i - qty)
            end
          end
        rescue StandardError => e
          Rails.logger.warn("[DealerOffer##{id}] dealer_product stock sync skipped: #{e.message}")
        end
      end
    end
  end

  def restore_quantity!(qty)
    qty = qty.to_i
    return unless qty.positive?

    with_lock do
      new_sold = [ sold_quantity.to_i - qty, 0 ].max
      update_columns(sold_quantity: new_sold, updated_at: Time.current)

      if dealer_product.present?
        dealer_product.update_columns(
          stock_quantity: dealer_product.stock_quantity.to_i + qty,
          updated_at: Time.current
        )
      end
    end
  end

  private

  def set_slug
    return if slug.present? && !device_model_changed?

    base = (device_model.presence || product&.name || "offer").to_s.parameterize
    base = "offer" if base.blank?

    candidate = base
    count = 1
    while DealerOffer.where(slug: candidate).where.not(id: id).exists?
      candidate = "#{base}-#{SecureRandom.hex(3)}"
      count += 1
      break if count > 15
    end
    self.slug = candidate
  end

  def auto_assign_dealer_defaults
    self.seller_code = dealer&.dealer_code if seller_code.blank?
    self.offer_starts_at = Time.current if offer_starts_at.blank?
    self.offer_ends_at = offer_starts_at + 7.days if offer_ends_at.blank?
  end

  def offer_window_valid
    return if offer_starts_at.blank? || offer_ends_at.blank?

    if offer_ends_at <= offer_starts_at
      errors.add(:offer_ends_at, "must be after the offer start date")
      return
    end

    # Max duration cannot exceed 7 days
    if (offer_ends_at - offer_starts_at) > (7.days + 1.minute)
      errors.add(:offer_ends_at, "duration cannot exceed 7 days from start date")
    end
  end

  def media_files_valid
    validate_attachment_set(:media)
  end

  def validate_pincodes_format
    return if pincodes.blank?

    invalid = pincodes.reject { |p| p.to_s.match?(/\A[1-9][0-9]{5}\z/) }
    return if invalid.blank?

    errors.add(:pincodes, "contain invalid pincodes: #{invalid.join(', ')}")
  end
end
