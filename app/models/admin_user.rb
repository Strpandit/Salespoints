class AdminUser < ApplicationRecord
  include CrossActorUniqueness
  include TokenRevocable
  has_secure_password validations: false
  acts_as_paranoid
  attr_accessor :generated_password
  include AttachableMediaValidations

  APPROVAL_STATUSES = %w[pending approved rejected].freeze
  PHONE_FORMAT = /\A[0-9]{10}\z/
  PAN_FORMAT = /\A[A-Z]{5}[0-9]{4}[A-Z]\z/
  IFSC_FORMAT = /\A[A-Z]{4}0[A-Z0-9]{6}\z/
  AADHAR_FORMAT = /\A[0-9]{12}\z/

  has_many :admin_roles, dependent: :destroy
  has_many :roles, through: :admin_roles
  has_many :notifications, as: :receiver, dependent: :destroy
  # Kept after the account is (soft) deleted so admins keep the approval history.
  has_many :deletion_requests, as: :requestable
  has_many :push_subscriptions, as: :subscriber, dependent: :destroy
  has_many :report_audit_logs, as: :user, dependent: :destroy
  has_many :support_tickets, foreign_key: 'admin_user_id', dependent: :destroy
  has_many :assigned_tickets, class_name: 'SupportTicket', foreign_key: 'assigned_to_id', dependent: :nullify
  has_many :ticket_messages, foreign_key: 'admin_user_id', dependent: :destroy
  has_many :contact_form_submissions, dependent: :destroy
  belongs_to :approved_by, class_name: "AdminUser", optional: true
  belongs_to :deleted_by, class_name: "AdminUser", optional: true
  has_many :deleted_admins, class_name: "AdminUser", foreign_key: :deleted_by_id

  has_many_attached :marksheets
  has_many_attached :aadhar_card
  has_one_attached :staff_profile_pic
  has_one_attached :pan_card
  has_one_attached :passbook

  enum :status, { active: 'active', inactive: 'inactive' }
  scope :approved, -> { where(approval_status: "approved") }
  scope :pending_approval, -> { where(approval_status: "pending") }

  validates :email,
    allow_blank: true,
    uniqueness: { case_sensitive: false },
    format: {
      with: /\A[a-zA-Z0-9.!#$%&'*+\/=?^_`{|}~-]+@
            [a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)*\.[a-zA-Z]{2,}\z/x
    }
  validates :phone, uniqueness: true, allow_blank: true
  validates :alternate_phone, allow_blank: true, uniqueness: true
  validates :phone, format: { with: PHONE_FORMAT, message: "must be a 10-digit number" }, allow_blank: true, if: :will_save_change_to_phone?
  validates :alternate_phone, format: { with: PHONE_FORMAT, message: "must be a 10-digit number" }, allow_blank: true, if: :will_save_change_to_alternate_phone?
  validates :pan_number, format: { with: PAN_FORMAT, message: "must be in the format ABCDE1234F" }, allow_blank: true, if: :will_save_change_to_pan_number?
  validates :ifsc_code, format: { with: IFSC_FORMAT, message: "must be in the format SBIN0001234" }, allow_blank: true, if: :will_save_change_to_ifsc_code?
  validates :aadhar_number, format: { with: AADHAR_FORMAT, message: "must be 12 digits" }, allow_blank: true, if: :will_save_change_to_aadhar_number?
  validates :salary, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true, if: -> { new_record? || will_save_change_to_salary? }
  validate :joining_date_must_be_valid
  validate :phone_input_must_be_numeric
  validates :approval_status, inclusion: { in: APPROVAL_STATUSES }

  validates_uniqueness_across_actors :email, :phone
  # validates :address, :aadhar_number, :pan_number, :bank_name, :bank_account_number,
  #           :ifsc_code, :account_holder_name, :tenth_school_name, :tenth_board,
  #           :tenth_passing_year, :tenth_percentage, :twelfth_school_name, :twelfth_board,
  #           :twelfth_passing_year, :twelfth_percentage, presence: true
  # validate :staff_profile_pic_presence_and_validity
  validate :attachments_validity
  validate :validate_pincodes_format
  validate :staff_profile_pic_must_be_image, if: -> { attachment_changes["staff_profile_pic"].present? }

  before_create :generate_password
  before_validation :normalize_email
  before_validation :normalize_phone
  before_validation :normalize_identity_fields

  def super_admin?
    is_super_admin || roles.active.exists?(name: "super_admin")
  end

  def accessible_pincodes
    return nil if super_admin?
    pincodes.presence || []
  end

  def can_access_pincode?(pincode)
    return true if super_admin?
    return false if pincodes.blank?
    pincodes.include?(pincode)
  end

  def accessible_dealers(dealers_scope = Dealer.all)
    return dealers_scope if super_admin?
    return dealers_scope.none if pincodes.blank?
    dealers_scope.where(pincode: pincodes)
  end

  def accessible_wholesale_posts(posts_scope = WholesalerPost.all)
    return posts_scope if super_admin?
    return posts_scope if approver_admin?

    return posts_scope.none if pincodes.blank?

    posts_scope.where("pincodes && ARRAY[?]::varchar[]", pincodes)
  end

  def accessible_dealer_offers(offers_scope = DealerOffer.all)
    return offers_scope if super_admin?
    return offers_scope if approver_admin?

    return offers_scope.none if pincodes.blank?

    offers_scope.where("pincodes && ARRAY[?]::varchar[]", pincodes)
  end

  def approver_admin?
    return true if super_admin?

    roles.active.any? { |role| role.name.to_s.strip.downcase.in?(["sub admin", "sub_admin"]) }
  end

  def full_name
    [first_name, last_name].compact.join(" ")
  end

  def can_access?(module_name, permission = :read)
    return true if super_admin?

    normalized_module = module_name.to_s
    required_permission = permission.to_s

    roles.active.any? do |role|
      permissions = role.permissions_for(normalized_module)
      permissions.include?(required_permission)
    end
  end

  def joining_form_completed?
    required_values = [
      address, aadhar_number, pan_number, bank_name, bank_account_number, ifsc_code,
      account_holder_name, tenth_school_name, tenth_board, tenth_passing_year,
      tenth_percentage, twelfth_school_name, twelfth_board, twelfth_passing_year,
      twelfth_percentage
    ]

    required_values.all?(&:present?) && staff_profile_pic.attached?
  end

  def approved?
    approval_status == "approved"
  end

  def generate_signup_token!
    token = SecureRandom.hex(20)
    pin = SecureRandom.random_number(100000..999999).to_s
    now = Time.current
    update!(
      signup_token: token,
      signup_token_sent_at: now,
      otp_pin: pin,
      otp_sent_at: now
    )
    token
  end

  def otp_valid?(otp)
    otp_pin.present? && otp_sent_at.present? && otp_sent_at > 10.minutes.ago &&
      ActiveSupport::SecurityUtils.secure_compare(otp_pin.to_s, otp.to_s.strip)
  end

  def token_valid?(token)
    signup_token.present? && signup_token.to_s == token.to_s && signup_token_sent_at.present? && signup_token_sent_at > 10.minutes.ago
  end

  def clear_otp!
    update!(
      otp_pin: nil,
      otp_sent_at: nil,
      signup_token: nil,
      signup_token_sent_at: nil
    )
  end

  private

  def normalize_email
    self.email = email.to_s.strip.downcase.presence
  end

  PHONE_ALLOWED_CHARS = /\A[0-9\s+\-()]*\z/

  def normalize_phone
    @phone_input_invalid = phone.to_s.present? && !phone.to_s.match?(PHONE_ALLOWED_CHARS)
    @alternate_phone_input_invalid = alternate_phone.to_s.present? && !alternate_phone.to_s.match?(PHONE_ALLOWED_CHARS)
    mobile = phone.to_s.gsub(/\D/, '').sub(/^0+/, '')
    mobile = mobile.delete_prefix("91") if mobile.length == 12 && mobile.start_with?("91")
    self.phone = mobile.presence
    alternate_mobile = alternate_phone.to_s.gsub(/\D/, '').sub(/^0+/, '')
    alternate_mobile = alternate_mobile.delete_prefix("91") if alternate_mobile.length == 12 && alternate_mobile.start_with?("91")
    self.alternate_phone = alternate_mobile.presence
    if country_code.present?
      self.country_code = "+#{country_code.gsub(/\D/, '')}"
    end
  end

  def normalize_identity_fields
    self.pan_number = pan_number.to_s.gsub(/\s+/, "").upcase.presence if pan_number_changed?
    self.ifsc_code = ifsc_code.to_s.gsub(/\s+/, "").upcase.presence if ifsc_code_changed?
    self.aadhar_number = aadhar_number.to_s.gsub(/\s+/, "").presence if aadhar_number_changed?
  end

  def phone_input_must_be_numeric
    errors.add(:phone, "must be a 10-digit number") if @phone_input_invalid
    errors.add(:alternate_phone, "must be a 10-digit number") if @alternate_phone_input_invalid
  end

  def joining_date_must_be_valid
    raw = joining_date_before_type_cast
    errors.add(:joining_date, "is not a valid date") if raw.present? && joining_date.nil?
  end

  def staff_profile_pic_must_be_image
    blob = staff_profile_pic.blob
    return unless blob

    type = blob.content_type.to_s
    type = inferred_content_type(blob) if type.blank? || type == "application/octet-stream"
    errors.add(:staff_profile_pic, "must be an image (JPG, PNG or WebP)") unless IMAGE_TYPES.include?(type)
  end

  def attachments_validity
    validate_document_attachment_set(:marksheets)
    validate_document_attachment_set(:aadhar_card)
    validate_document_attachment(:staff_profile_pic)
    validate_document_attachment(:pan_card)
    validate_document_attachment(:passbook)
  end

  def generate_password
    return if password.present?

    generated_password = SecureRandom.urlsafe_base64(12)
    self.generated_password = generated_password
    self.password = generated_password
    self.password_confirmation = generated_password
  end

  def validate_pincodes_format
    return if pincodes.blank?
    invalid = pincodes.reject { |p| p.to_s.match?(/\A[1-9][0-9]{5}\z/) }
    if invalid.present?
      errors.add(:pincodes, "contain invalid pincodes: #{invalid.join(', ')}")
    end
  end
end
