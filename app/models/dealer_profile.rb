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

  validates :pan_number, format: { with: /\A[A-Z]{5}[0-9]{4}[A-Z]\z/, message: "must be in the format ABCDE1234F" }, allow_blank: true, if: :will_save_change_to_pan_number?
  validates :gst_number, format: { with: /\A[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]\z/, message: "must be a valid 15-character GSTIN" }, allow_blank: true, if: :will_save_change_to_gst_number?
  validates :ifsc_code, format: { with: /\A[A-Z]{4}0[A-Z0-9]{6}\z/, message: "must be in the format SBIN0001234" }, allow_blank: true, if: :will_save_change_to_ifsc_code?
  validates :bank_account_number, format: { with: /\A[0-9]{9,18}\z/, message: "must be 9 to 18 digits" }, allow_blank: true, if: :will_save_change_to_bank_account_number?
  before_validation :normalize_identity_fields

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

  def normalize_identity_fields
    self.pan_number = pan_number.to_s.gsub(/\s+/, "").upcase.presence if pan_number_changed?
    self.gst_number = gst_number.to_s.gsub(/\s+/, "").upcase.presence if gst_number_changed?
    self.ifsc_code = ifsc_code.to_s.gsub(/\s+/, "").upcase.presence if ifsc_code_changed?
    self.bank_account_number = bank_account_number.to_s.gsub(/\s+/, "").presence if bank_account_number_changed?
  end

  def attachments_validity
    validate_attachment_set(:store_image, required: new_record?)
    validate_document_attachment_set(:aadhar_card)
    validate_document_attachment(:pan_card)
    validate_document_attachment(:gst_certificate)
    validate_document_attachment(:cancel_cheque)
    validate_document_attachment_set(:brand_invoices, required: false)
  end
end
