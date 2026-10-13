class DealerProfileSerializer < ApplicationSerializer
  attributes :business_name, :business_type, :gst_number, :pan_number,
             :aadhar_number, :bank_name, :bank_account_number, :masked_bank_account_number, :ifsc_code,
             :account_holder_name, :bank_verification_status, :bank_verification_reference,
             :bank_verified_at, :verified_bank_name, :verified_name_at_bank, :last_bank_verification_error,
             :bank_change_status, :bank_change_requested_at, :bank_change_reason, :bank_change_reviewed_at,
             :bank_change_rejection_reason, :bank_locked,
             :business_address, :business_contact_number, :business_email,
             :work_category, :associated_brands, :store_image, :aadhar_card, :pan_card, 
             :gst_certificate, :cancel_cheque, :brand_invoices, :is_verified, :created_at, :updated_at

  # See DealerSerializer#redacted?: public/shared listings must not expose KYC, bank or tax details.
  def redacted?
    return false unless options[:redact_dealer]
    return false if options[:viewer].to_s == "admin"

    !(options[:viewer].to_s == "dealer" && options[:viewer_id].to_s == object.dealer_id.to_s)
  end

  def gst_number
    redacted? ? nil : object.gst_number
  end

  def pan_number
    redacted? ? nil : object.pan_number
  end

  def aadhar_number
    redacted? ? nil : object.aadhar_number
  end

  def bank_name
    redacted? ? nil : object.bank_name
  end

  def bank_account_number
    redacted? ? nil : object.bank_account_number
  end

  def masked_bank_account_number
    redacted? ? nil : object.masked_bank_account_number
  end

  def ifsc_code
    redacted? ? nil : object.ifsc_code
  end

  def account_holder_name
    redacted? ? nil : object.account_holder_name
  end

  def bank_verification_status
    redacted? ? nil : object.bank_verification_status
  end

  def bank_verification_reference
    redacted? ? nil : object.bank_verification_reference
  end

  def bank_verified_at
    redacted? ? nil : object.bank_verified_at
  end

  def verified_bank_name
    redacted? ? nil : object.verified_bank_name
  end

  def verified_name_at_bank
    redacted? ? nil : object.verified_name_at_bank
  end

  def last_bank_verification_error
    redacted? ? nil : object.last_bank_verification_error
  end

  def bank_change_status
    redacted? ? nil : object.bank_change_status
  end

  def bank_change_requested_at
    redacted? ? nil : object.bank_change_requested_at
  end

  def bank_change_reason
    redacted? ? nil : object.bank_change_reason
  end

  def bank_change_reviewed_at
    redacted? ? nil : object.bank_change_reviewed_at
  end

  def bank_change_rejection_reason
    redacted? ? nil : object.bank_change_rejection_reason
  end

  def bank_locked
    redacted? ? nil : object.bank_locked?
  end

  def store_image
    object.store_image.map { |file| file_payload(file) }
  end

  def aadhar_card
    return [] if redacted?

    object.aadhar_card.map { |file| file_payload(file, expires_in: KYC_LINK_TTL) }
  end

  def pan_card
    return nil if redacted?
    return nil unless object.pan_card.attached?

    file_payload(object.pan_card, expires_in: KYC_LINK_TTL)
  end

  def gst_certificate
    return nil if redacted?
    return nil unless object.gst_certificate.attached?

    file_payload(object.gst_certificate, expires_in: KYC_LINK_TTL)
  end

  def cancel_cheque
    return nil if redacted?
    return nil unless object.cancel_cheque.attached?

    file_payload(object.cancel_cheque, expires_in: KYC_LINK_TTL)
  end

  def brand_invoices
    return [] if redacted?

    object.brand_invoices.map { |file| file_payload(file) }
  end

  private

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
