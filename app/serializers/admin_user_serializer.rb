class AdminUserSerializer < ApplicationSerializer
  attributes :first_name, :last_name, :email, :phone, :alternate_phone, :address, :salary,
             :aadhar_number, :pan_number, :bank_name, :bank_account_number,
             :ifsc_code, :account_holder_name, :tenth_school_name, :tenth_board,
             :tenth_passing_year, :tenth_percentage, :twelfth_school_name,
             :twelfth_board, :twelfth_passing_year, :twelfth_percentage, :status, :pincodes,
             :country_code, :is_super_admin, :full_name, :pending_deletion_request, :joining_date,
             :role, :staff_profile_pic, :aadhar_card, :pan_card, :passbook, :marksheets, :joining_form_completed,
             :approval_status, :approved_at, :approved_by_name, :otp_verified, :deleted_at, :deleted_by

  def pending_deletion_request
    object.deletion_requests.pending.exists?
  end

  def joining_form_completed
    object.joining_form_completed?
  end

  def otp_verified
    object.otp_pin.blank?
  end

  def role
    object.roles&.map do |role|
      {
        id: role.id,
        name: role.name,
        is_active: role.is_active,
        module_access: role.module_access,
        module_permissions: role.module_permissions
      }
    end
  end

  def staff_profile_pic
    return nil unless object.staff_profile_pic.attached?

    file_payload(object.staff_profile_pic)
  end

  def salary
    can_view_sensitive? ? object.salary : nil
  end

  def bank_account_number
    can_view_sensitive? ? object.bank_account_number : mask_value(object.bank_account_number)
  end

  def aadhar_number
    can_view_sensitive? ? object.aadhar_number : mask_value(object.aadhar_number)
  end

  def pan_number
    can_view_sensitive? ? object.pan_number : mask_value(object.pan_number)
  end

  def aadhar_card
    return [] unless can_view_sensitive?
    object.aadhar_card.map { |file| file_payload(file, expires_in: KYC_LINK_TTL) }
  end

  def pan_card
    return nil unless can_view_sensitive? && object.pan_card.attached?

    file_payload(object.pan_card, expires_in: KYC_LINK_TTL)
  end

  def passbook
    return nil unless can_view_sensitive? && object.passbook.attached?

    file_payload(object.passbook, expires_in: KYC_LINK_TTL)
  end

  def approved_by_name
    object.approved_by&.full_name
  end

  def marksheets
    return [] unless can_view_sensitive?
    object.marksheets.map { |file| file_payload(file) }
  end

  private

  def can_view_sensitive?
    viewer = options[:current_admin]
    return true if viewer.blank?
    return true if viewer.super_admin?
    return true if viewer.id == object.id
    return true if object.respond_to?(:created_by_id) && object.created_by_id == viewer.id

    false
  end

  def mask_value(val)
    return nil if val.blank?
    str = val.to_s
    str.length > 4 ? ("*" * (str.length - 4)) + str[-4..] : "****"
  end

  KYC_LINK_TTL = 2.hours

  def file_payload(file, expires_in: nil)
    host = options[:base_url] || Rails.application.config.active_storage.default_url_options&.dig(:host)
    url_options = { host: host }
    url_options[:expires_in] = expires_in if expires_in
    {
      id: file.id,
      url: Rails.application.routes.url_helpers.rails_blob_url(file, **url_options),
      filename: file.filename.to_s,
      content_type: file.content_type.to_s
    }
  end
end
