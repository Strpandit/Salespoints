class DealerSerializer < ApplicationSerializer

  attributes :first_name, :last_name, :email, :phone, :gender, :country_code, :status, :dealer_code, :full_name, :created_at, :updated_at,
             :pending_deletion_request, :settlement_balance, :otp_verified, :pincode
 
  has_one :dealer_profile
  has_one :dealer_location

  # Set (via the controller's viewer_context) on public/shared listings such as the shop and dealer-product
  # lists, where the dealer is nested next to a product. Only admins and the dealer themself keep the private fields.
  def redacted?
    return false unless options[:redact_dealer]
    return false if options[:viewer].to_s == "admin"

    !(options[:viewer].to_s == "dealer" && options[:viewer_id].to_s == object.id.to_s)
  end

  def email
    redacted? ? nil : object.email
  end

  def pending_deletion_request
    return nil if redacted?

    object.deletion_requests.pending.exists?
  end

  def settlement_balance
    return nil if redacted?

    object.settlement_balance.to_f
  end

  def otp_verified
    object.otp_verified?
  end
end
