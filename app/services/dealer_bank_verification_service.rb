class DealerBankVerificationService
  CACHE_PREFIX = "dealer_bank_verification".freeze
  CACHE_TTL = 30.minutes
  RATE_LIMIT_PREFIX = "dealer_bank_verify_rate".freeze
  MAX_ATTEMPTS_PER_24H = 3
  COOLDOWN_SECONDS = 60

  IFSC_REGEX = /\A[A-Z]{4}0[A-Z0-9]{6}\z/i
  ACCOUNT_NUMBER_REGEX = /\A\d{9,18}\z/

  VerificationResult = Struct.new(
    :verification_reference,
    :cashfree_reference_id,
    :status,
    :bank_name,
    :name_at_bank,
    :account_number,
    :ifsc_code,
    :account_holder_name,
    :bank_payload,
    :ifsc_payload,
    :attempts_remaining,
    :cooldown_seconds,
    keyword_init: true
  )

  def initialize(dealer:)
    @dealer = dealer
    @cashfree = CashfreeService.new
  end

  def verify!(account_number:, confirm_account_number:, account_holder_name:, ifsc_code:, is_admin: false)
    normalized_account_number = account_number.to_s.gsub(/\s+/, "")
    normalized_confirm_account = confirm_account_number.to_s.gsub(/\s+/, "")
    normalized_ifsc = ifsc_code.to_s.strip.upcase
    normalized_holder_name = account_holder_name.to_s.squish

    # 1. Strict Input Validations
    raise StandardError, "Account number is required" if normalized_account_number.blank?
    raise StandardError, "Confirm account number is required" if normalized_confirm_account.blank?
    raise StandardError, "Account numbers do not match" unless normalized_account_number == normalized_confirm_account
    raise StandardError, "Account number must be 9 to 18 numeric digits" unless normalized_account_number =~ ACCOUNT_NUMBER_REGEX

    raise StandardError, "IFSC code is required" if normalized_ifsc.blank?
    raise StandardError, "Invalid IFSC code format (e.g. SBIN0000001)" unless normalized_ifsc =~ IFSC_REGEX

    raise StandardError, "Account holder name is required" if normalized_holder_name.blank?
    if normalized_holder_name.length < 2
      raise StandardError, "Account holder name must be at least 2 characters"
    end

    # 2. Fast-Path: If already verified with exact same details in DB, return 0-cost verification
    if already_verified_in_db?(account_number: normalized_account_number, ifsc: normalized_ifsc)
      cached_ref = @dealer.dealer_profile&.bank_verification_reference.presence || "DB-VERIFIED-#{@dealer.id}-#{SecureRandom.hex(4).upcase}"
      existing_bank = @dealer.dealer_profile&.bank_name.presence || @dealer.dealer_profile&.verified_bank_name.presence || default_bank_name(normalized_ifsc)
      
      result = VerificationResult.new(
        verification_reference: cached_ref,
        cashfree_reference_id: nil,
        status: "verified",
        bank_name: existing_bank,
        name_at_bank: @dealer.dealer_profile&.verified_name_at_bank.presence || normalized_holder_name,
        account_number: normalized_account_number,
        ifsc_code: normalized_ifsc,
        account_holder_name: normalized_holder_name,
        bank_payload: { "status" => "ALREADY_VERIFIED_IN_DB", "cached" => true },
        ifsc_payload: nil,
        attempts_remaining: attempts_remaining,
        cooldown_seconds: 0
      )
      cache_verification(result)
      return result
    end

    # 3. Duplicate Account Check across active dealers (Fraud prevention)
    if duplicate_account_on_other_dealer?(normalized_account_number)
      raise StandardError, "This bank account is already registered with another active dealer. Please contact support or submit for manual admin review."
    end

    # 4. Rate Limiting: 60-second cooldown check
    cooldown_left = cooldown_remaining_seconds
    if cooldown_left > 0
      raise StandardError, "Please wait #{cooldown_left}s cooldown before attempting verification again."
    end

    # 5. Rate Limiting: 3 attempts in 24 hours
    attempts_used = attempts_used_in_24h
    if attempts_used >= MAX_ATTEMPTS_PER_24H
      raise StandardError, "Maximum limit of #{MAX_ATTEMPTS_PER_24H} verification attempts in 24 hours reached for this account. Please verify manually or try after 24 hours."
    end

    # 6. Verify with Cashfree (Single API Hit for both IFSC + Account)
    raise StandardError, "Payment service is temporarily unconfigured. Please submit for manual admin approval." unless @cashfree.configured?

    # Record rate limit attempt
    record_attempt!

    verification_reference = "BANKVERIFY-#{@dealer.id}-#{SecureRandom.hex(6).upcase}"
    
    bank_payload = @cashfree.verify_bank_account(
      account_holder_name: normalized_holder_name,
      phone: @dealer.phone,
      bank_account: normalized_account_number,
      ifsc_code: normalized_ifsc,
      reference_id: verification_reference
    )

    cashfree_reference_id = bank_payload["reference_id"]
    bank_name = extract_bank_name_from_payload(bank_payload).presence || default_bank_name(normalized_ifsc)

    account_status = bank_payload["account_status"].to_s.upcase
    account_status_code = bank_payload["account_status_code"].to_s.upcase

    if account_status == "RECEIVED" && account_status_code == "VALIDATION_IN_PROGRESS"
      result = VerificationResult.new(
        verification_reference: verification_reference,
        cashfree_reference_id: cashfree_reference_id,
        status: "pending",
        bank_name: bank_name,
        name_at_bank: nil,
        account_number: normalized_account_number,
        ifsc_code: normalized_ifsc,
        account_holder_name: normalized_holder_name,
        bank_payload: bank_payload,
        ifsc_payload: nil,
        attempts_remaining: attempts_remaining,
        cooldown_seconds: COOLDOWN_SECONDS
      )
      cache_verification(result)
      return result
    end

    ensure_bank_account_verified!(bank_payload)
    name_at_bank = extract_name_at_bank(bank_payload)

    if name_at_bank.present? && !name_match?(expected: normalized_holder_name, actual: name_at_bank)
      raise StandardError, "Account holder name does not match the bank record (#{name_at_bank})"
    end

    result = VerificationResult.new(
      verification_reference: verification_reference,
      cashfree_reference_id: cashfree_reference_id,
      status: "verified",
      bank_name: bank_name,
      name_at_bank: name_at_bank.presence || normalized_holder_name,
      account_number: normalized_account_number,
      ifsc_code: normalized_ifsc,
      account_holder_name: normalized_holder_name,
      bank_payload: bank_payload,
      ifsc_payload: nil,
      attempts_remaining: attempts_remaining,
      cooldown_seconds: COOLDOWN_SECONDS
    )

    cache_verification(result)
    result
  end

  def consume_verified_payload!(verification_reference:, account_number:, ifsc_code:, account_holder_name:)
    payload = Rails.cache.read(cache_key(verification_reference))
    raise StandardError, "Bank verification expired or not found. Please verify again." if payload.blank?

    unless payload[:dealer_id].to_i == @dealer.id
      raise StandardError, "Bank verification does not belong to this dealer"
    end

    normalized_account_number = account_number.to_s.gsub(/\s+/, "")
    normalized_ifsc = ifsc_code.to_s.strip.upcase
    normalized_holder_name = account_holder_name.to_s.squish

    unless payload[:account_number].to_s == normalized_account_number &&
           payload[:ifsc_code].to_s == normalized_ifsc &&
           payload[:account_holder_name].to_s.casecmp?(normalized_holder_name)
      raise StandardError, "Verified bank details do not match the current form"
    end

    payload
  end

  def persist_verified_profile!(profile:, verification_payload:)
    profile.assign_attributes(
      bank_name: verification_payload[:bank_name],
      verified_bank_name: verification_payload[:bank_name],
      bank_account_number: verification_payload[:account_number],
      ifsc_code: verification_payload[:ifsc_code],
      account_holder_name: verification_payload[:account_holder_name],
      verified_name_at_bank: verification_payload[:name_at_bank],
      bank_verification_status: "verified",
      bank_verification_reference: verification_payload[:verification_reference],
      bank_verified_at: Time.current,
      last_bank_verification_error: nil,
      bank_verification_payload: {
        verified_at: Time.current.iso8601,
        bank_verification: verification_payload[:bank_payload],
        ifsc_verification: verification_payload[:ifsc_payload]
      }
    )
    profile
  end

  def request_manual_approval!(profile:, account_number:, confirm_account_number:, account_holder_name:, ifsc_code:, bank_name: nil)
    normalized_account_number = account_number.to_s.gsub(/\s+/, "")
    normalized_confirm_account = confirm_account_number.to_s.gsub(/\s+/, "")
    normalized_ifsc = ifsc_code.to_s.strip.upcase
    normalized_holder_name = account_holder_name.to_s.squish

    raise StandardError, "Account number is required" if normalized_account_number.blank?
    raise StandardError, "Account numbers do not match" unless normalized_account_number == normalized_confirm_account
    raise StandardError, "Account number must be 9 to 18 digits" unless normalized_account_number =~ ACCOUNT_NUMBER_REGEX
    raise StandardError, "Invalid IFSC code" unless normalized_ifsc =~ IFSC_REGEX
    raise StandardError, "Account holder name is required" if normalized_holder_name.blank?

    final_bank_name = bank_name.presence || profile.bank_name.presence || default_bank_name(normalized_ifsc)

    profile.assign_attributes(
      bank_name: final_bank_name,
      bank_account_number: normalized_account_number,
      ifsc_code: normalized_ifsc,
      account_holder_name: normalized_holder_name,
      bank_verification_status: "pending_admin_approval",
      last_bank_verification_error: nil
    )
    profile.save!
    profile
  end

  def admin_manual_approve!(profile:, admin_user:)
    raise StandardError, "Dealer profile is missing bank details" if profile.bank_account_number.blank? || profile.ifsc_code.blank?

    profile.assign_attributes(
      bank_verification_status: "verified",
      bank_verified_at: Time.current,
      verified_bank_name: profile.bank_name,
      verified_name_at_bank: profile.account_holder_name,
      bank_verification_reference: "ADMIN-MANUAL-#{admin_user.id}-#{Time.current.to_i}",
      last_bank_verification_error: nil,
      bank_verification_payload: {
        verified_at: Time.current.iso8601,
        verified_by_admin_id: admin_user.id,
        verified_by_admin_email: admin_user.email,
        method: "manual_cheque_review"
      }
    )
    profile.save!
    profile
  end

  def mark_unverified!(profile:, reason: nil)
    profile.assign_attributes(
      bank_verification_status: "unverified",
      bank_verification_reference: nil,
      bank_verified_at: nil,
      verified_bank_name: nil,
      verified_name_at_bank: nil,
      last_bank_verification_error: reason,
      bank_verification_payload: {}
    )
  end

  # Rate limiting helpers
  def attempts_used_in_24h
    Rails.cache.read(attempts_cache_key).to_i
  end

  def attempts_remaining
    [MAX_ATTEMPTS_PER_24H - attempts_used_in_24h, 0].max
  end

  def cooldown_remaining_seconds
    last_timestamp = Rails.cache.read(cooldown_cache_key).to_i
    return 0 if last_timestamp.zero?

    elapsed = Time.current.to_i - last_timestamp
    remaining = COOLDOWN_SECONDS - elapsed
    remaining.positive? ? remaining : 0
  end

  private

  def record_attempt!
    current = attempts_used_in_24h
    Rails.cache.write(attempts_cache_key, current + 1, expires_in: 24.hours)
    Rails.cache.write(cooldown_cache_key, Time.current.to_i, expires_in: COOLDOWN_SECONDS.seconds)
  end

  def attempts_cache_key
    "#{RATE_LIMIT_PREFIX}:attempts:#{@dealer.id}"
  end

  def cooldown_cache_key
    "#{RATE_LIMIT_PREFIX}:cooldown:#{@dealer.id}"
  end

  def already_verified_in_db?(account_number:, ifsc:)
    profile = @dealer.dealer_profile
    return false unless profile&.bank_verified?

    profile.bank_account_number.to_s == account_number &&
      profile.ifsc_code.to_s.upcase == ifsc
  end

  def duplicate_account_on_other_dealer?(account_number)
    DealerProfile.where.not(dealer_id: @dealer.id)
                 .where(bank_account_number: account_number, bank_verification_status: "verified")
                 .exists?
  end

  def default_bank_name(ifsc_code)
    prefix = ifsc_code.to_s[0..3].upcase
    bank_map = {
      "SBIN" => "State Bank of India",
      "HDFC" => "HDFC Bank",
      "ICIC" => "ICICI Bank",
      "PUNB" => "Punjab National Bank",
      "BARB" => "Bank of Baroda",
      "CNRB" => "Canara Bank",
      "UBIN" => "Union Bank of India",
      "BKID" => "Bank of India",
      "IOBA" => "Indian Overseas Bank",
      "UTIB" => "Axis Bank",
      "KKBK" => "Kotak Mahindra Bank",
      "IDFB" => "IDFC FIRST Bank",
      "YESB" => "Yes Bank",
      "INDB" => "IndusInd Bank",
      "MAHB" => "Bank of Maharashtra",
      "PSIB" => "Punjab & Sind Bank",
      "UCBA" => "UCO Bank"
    }
    bank_map[prefix] || "#{prefix} Bank"
  end

  def extract_bank_name_from_payload(bank_payload)
    bank_payload["bank_name"].presence ||
      bank_payload["bankName"].presence ||
      bank_payload.dig("data", "bank_name").presence ||
      bank_payload.dig("data", "bankName").presence
  end

  def extract_name_at_bank(bank_payload)
    bank_payload["name_at_bank"].presence ||
      bank_payload["nameAtBank"].presence ||
      bank_payload["beneName"].presence ||
      bank_payload.dig("data", "name_at_bank").presence ||
      bank_payload.dig("data", "nameAtBank").presence ||
      bank_payload.dig("data", "beneficiary_name").presence
  end

  def ensure_bank_account_verified!(bank_payload)
    account_status = bank_payload["account_status"].to_s.upcase
    account_status_code = bank_payload["account_status_code"].to_s.upcase

    return if account_status == "VALID" &&
              account_status_code == "ACCOUNT_IS_VALID"

    account_exists = bank_payload["accountExists"]
    account_exists = bank_payload.dig("data", "accountExists") if account_exists.nil?
    account_exists = bank_payload.dig("data", "account_exists") if account_exists.nil?

    if account_exists.present?
      return if ActiveModel::Type::Boolean.new.cast(account_exists)
    end

    message = bank_payload["message"].presence ||
              bank_payload["subCodeMessage"].presence ||
              bank_payload.dig("data", "message").presence ||
              "Bank account verification failed"
    raise StandardError, message
  end

  def name_match?(expected:, actual:)
    normalize_name(expected) == normalize_name(actual)
  end

  def normalize_name(value)
    value.to_s.downcase.gsub(/[^a-z0-9]/, "")
  end

  def cache_verification(result)
    Rails.cache.write(
      cache_key(result.verification_reference),
      {
        dealer_id: @dealer.id,
        verification_reference: result.verification_reference,
        cashfree_reference_id: result.cashfree_reference_id,
        status: result.status,
        bank_name: result.bank_name,
        name_at_bank: result.name_at_bank,
        account_number: result.account_number,
        ifsc_code: result.ifsc_code,
        account_holder_name: result.account_holder_name,
        bank_payload: result.bank_payload,
        ifsc_payload: result.ifsc_payload
      },
      expires_in: CACHE_TTL
    )
  end

  def cache_key(verification_reference)
    "#{CACHE_PREFIX}:#{@dealer.id}:#{verification_reference}"
  end
end
