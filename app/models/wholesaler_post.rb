class WholesalerPost < ApplicationRecord
  include AttachableMediaValidations
  include LiveDuration

  belongs_to :dealer
  belongs_to :dealer_product, optional: true
  belongs_to :reviewed_by_admin, class_name: "AdminUser", optional: true
  has_many :wholesaler_post_ratings, dependent: :destroy
  has_many_attached :media

  APPROVE_STATUSES = %w[pending approved rejected].freeze

  validates :title, presence: true
  validates :approve_status, inclusion: { in: APPROVE_STATUSES }
  validates :price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :stock_quantity, numericality: { greater_than_or_equal_to: 0 }
  validates :rating, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 5 }, allow_nil: true
  validates :rating_count, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :min_order_quantity, numericality: { only_integer: true, greater_than_or_equal_to: 2, message: "must be a whole number of at least 2" }
  validate :min_order_quantity_within_stock, if: :listing_edit
  validate :media_files_valid
  validate :validate_pincodes_format

  attr_accessor :listing_edit
  after_save { self.listing_edit = false }

  before_validation :set_default_mf_year, on: :create
  LIVE_UNTIL_SQL = "(COALESCE(wholesaler_posts.reuploaded_at, wholesaler_posts.created_at) + (wholesaler_posts.live_days * INTERVAL '1 day'))".freeze

  scope :visible_to_marketplace, -> {
    joins(:dealer)
      .where(dealers: { deleted_at: nil, status: "active" })
      .where(approve_status: "approved")
      .where("#{LIVE_UNTIL_SQL} > ?", Time.current)
  }
  scope :live_window_open, -> { where("#{LIVE_UNTIL_SQL} > ?", Time.current) }
  scope :live_window_closed, -> { where("#{LIVE_UNTIL_SQL} <= ?", Time.current) }
  scope :by_pincode, ->(pincode) { where("? = ANY(pincodes)", pincode) }
  scope :by_pincodes, ->(pincodes) { where("pincodes && ARRAY[?]::varchar[]", pincodes) }
  scope :approved_and_live, -> { where(approve_status: "approved") }
  
  def effective_hsn_code
    return hsn_code if hsn_code.present?
    return dealer_product&.effective_hsn_code if dealer_product.present?
    nil
  end
  
  def visible_to_others?
    approve_status == "approved" && !is_expired?
  end

  def visible_until
    base_date = reuploaded_at.presence || created_at
    base_date&.+(live_duration)
  end

  def effective_min_order_quantity
    moq = [ min_order_quantity.to_i, 2 ].max
    stock = stock_quantity.to_i
    stock.positive? && stock < moq ? stock : moq
  end

  def can_reupload?
   approve_status == "approved" && is_expired?
  end

  def reupload!(new_live_days: nil)
    return false unless can_reupload?

    self.live_days = new_live_days.to_i if new_live_days.present?

    update!(
      approve_status: 'pending',
      reviewed_at: nil,
      rejection_reason: nil,
      reviewed_by_admin: nil,
      updated_at: Time.current,
      reuploaded_at: Time.current
    )
  end

  def is_expired?
    visible_until.present? && visible_until <= Time.current
  end

  private

  def set_default_mf_year
    self.mf_year = Time.current.strftime("%m/%Y") if mf_year.blank?
  end

  def min_order_quantity_within_stock
    return if min_order_quantity.blank? || stock_quantity.to_i <= 0
    return if min_order_quantity.to_i <= stock_quantity.to_i

    errors.add(:base, "Minimum order quantity (#{min_order_quantity}) cannot be more than available stock (#{stock_quantity.to_i})")
  end

  def media_files_valid
    validate_attachment_set(:media)
  end

  def validate_pincodes_format
    return if pincodes.blank?
    invalid = pincodes.reject { |p| p.to_s.match?(/\A[1-9][0-9]{5}\z/) }
    if invalid.present?
      errors.add(:pincodes, "contain invalid pincodes: #{invalid.join(', ')}")
    end
  end
end
