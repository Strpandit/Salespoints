class ProductVariantColor < ApplicationRecord
  include AttachableMediaValidations
  include PrimaryMediaAttachable

  belongs_to :product
  belongs_to :product_variant, optional: true

  has_many_attached :media
  attr_accessor :purge_media_blob_ids

  validates :color_name, presence: true
  validate :media_files_valid

  private

  def media_files_valid
    validate_attachment_set(:media)
  end
end
