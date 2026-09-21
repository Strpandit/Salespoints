class DealerProfile < ApplicationRecord
  include AttachableMediaValidations

  BANK_VERIFICATION_STATUSES = %w[unverified verified failed pending_admin_approval].freeze
  BANK_CHANGE_STATUSES = %w[none pending approved rejected].freeze

  belongs_to :dealer
  has_many_attached :store_image
  has_many_attached :aadhar_card
  has_one_attached :pan_card
  has_one_attached :gst_certificate
  has_one_attached :cancel_cheque
  has_many_attached :brand_invoices

  validates :business_name, :aadhar_number, presence: true
  validates :bank_verification_status, inclusion: { in: BANK_VERIFICATION_STATUSES }
  validates :bank_change_status, inclusion: { in: BANK_CHANGE_STATUSES }, allow_nil: true
  validate :attachments_validity

  def bank_verified?
    bank_verification_status == "verified" &&
      bank_verified_at.present? &&
      bank_account_number.present? &&
      ifsc_code.present?
  end

  def bank_locked?
    bank_verified? && bank_change_status != "approved"
  end

  def bank_change_pending?
    bank_change_status == "pending"
  end

  def bank_change_approved?
    bank_change_status == "approved"
  end

  def masked_bank_account_number
    return nil if bank_account_number.blank?

    "XXXXXX#{bank_account_number.to_s.last(4)}"
  end

  private

  def attachments_validity
    validate_attachment_set(:store_image, required: new_record?)
    validate_document_attachment_set(:aadhar_card)
    validate_document_attachment(:pan_card)
    validate_document_attachment(:gst_certificate)
    validate_document_attachment(:cancel_cheque)
    validate_document_attachment_set(:brand_invoices, required: false)
  end
end
