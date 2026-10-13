class CatFilter < ApplicationRecord
  belongs_to :category

  DATA_TYPES = %w[string number boolean select].freeze

  validates :name, presence: true, length: { maximum: 100 },
                   uniqueness: { scope: :category_id, case_sensitive: false, message: "already exists for this category" }
  validates :data_type, inclusion: { in: DATA_TYPES }

  scope :mandatory, -> { where(is_mandatory: true) }
  scope :optional, -> { where(is_mandatory: false) }
  scope :for_category, ->(cat_id) { where(category_id: cat_id) }
  scope :ordered, -> { order(display_order: :asc, id: :asc) }

  validate :select_requires_options

  before_save :normalize_options

  private

  def select_requires_options
    return unless data_type == "select"
    if Array(options).map(&:to_s).map(&:strip).reject(&:blank?).empty?
      errors.add(:options, "must have at least one option for a select filter")
    end
  end

  def normalize_options
    if data_type == "select"
      self.options = Array(options).map(&:to_s).map(&:strip).reject(&:blank?)
    else
      self.options = [] if options.nil?
    end
  end
end

