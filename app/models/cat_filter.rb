class CatFilter < ApplicationRecord
  belongs_to :category

  DATA_TYPES = %w[string number boolean select].freeze

  validates :name, presence: true
  validates :data_type, inclusion: { in: DATA_TYPES }

  scope :mandatory, -> { where(is_mandatory: true) }
  scope :optional, -> { where(is_mandatory: false) }
  scope :for_category, ->(cat_id) { where(category_id: cat_id) }
  scope :ordered, -> { order(display_order: :asc, id: :asc) }

  before_save :normalize_options

  private

  def normalize_options
    if data_type == "select"
      self.options = Array(options).map(&:to_s).map(&:strip).reject(&:blank?)
    else
      self.options = [] if options.nil?
    end
  end
end

