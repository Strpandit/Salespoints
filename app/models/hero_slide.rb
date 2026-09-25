class HeroSlide < ApplicationRecord
  THEMES = %w[blue indigo purple emerald rose].freeze
  IMAGE_TYPES = %w[image/jpeg image/jpg image/png image/webp].freeze
  MAX_IMAGE_SIZE = 5.megabytes
  LINK_FORMAT = %r{\A(/[^\s]*|https?://[^\s]+)\z}

  has_one_attached :image

  validates :highlight, presence: true, length: { maximum: 80 }
  validates :title, :badge, :discount_text, length: { maximum: 60 }
  validates :subtitle, length: { maximum: 220 }
  validates :cta_label, presence: true, length: { maximum: 30 }
  validates :secondary_cta_label, length: { maximum: 30 }
  validates :theme, inclusion: { in: THEMES }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :link_url, :secondary_link_url, format: { with: LINK_FORMAT, message: "must start with / or http(s)://" }, allow_blank: true
  validate :image_valid
  validate :schedule_valid

  scope :ordered, -> { order(:position, :id) }
  scope :visible, lambda {
    now = Time.current
    where(is_active: true)
      .where("hero_slides.starts_at IS NULL OR hero_slides.starts_at <= ?", now)
      .where("hero_slides.ends_at IS NULL OR hero_slides.ends_at > ?", now)
  }

  # live | scheduled | expired | hidden — shown on the admin list.
  def display_status
    return "hidden" unless is_active?
    return "scheduled" if starts_at.present? && starts_at > Time.current
    return "expired" if ends_at.present? && ends_at <= Time.current

    "live"
  end

  private

  def image_valid
    unless image.attached?
      errors.add(:image, "is required")
      return
    end

    errors.add(:image, "must be JPG, PNG or WEBP") unless IMAGE_TYPES.include?(image.blob.content_type)
    errors.add(:image, "must be smaller than 5 MB") if image.blob.byte_size > MAX_IMAGE_SIZE
  end

  def schedule_valid
    return if starts_at.blank? || ends_at.blank?

    errors.add(:ends_at, "must be after the start time") if ends_at <= starts_at
  end
end
