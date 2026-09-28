module Api
  class AuthController < ApplicationController
    skip_before_action :authenticate_request!

    # Per-IP ceilings on top of the per-account cooldown in OtpService: stops OTP/signup spam
    # (WhatsApp cost) and bulk guessing from one source.
    rate_limit to: 20, within: 10.minutes, only: :send_otp, name: "otp-send", by: -> { client_ip },
               with: -> { render json: { error: "Too many OTP requests. Please try again later." }, status: :too_many_requests }
    rate_limit to: 30, within: 10.minutes, only: :verify_otp, name: "otp-verify", by: -> { client_ip },
               with: -> { render json: { error: "Too many attempts. Please try again later." }, status: :too_many_requests }

    OTP_SCOPE = "customer_login".freeze
    # Login/Signup via email or phone + 6-digit WhatsApp OTP (Account only)
    def send_otp
      identifier = params[:identifier].to_s.strip
      signup = ActiveModel::Type::Boolean.new.cast(params[:signup])

      if identifier.blank?
        return render json: { error: "Email or Phone number is required" }, status: :unprocessable_entity
      end

      is_email = identifier.include?('@')
      normalized_phone = is_email ? nil : identifier.gsub(/\D/, '').last(10)

      if !is_email && (normalized_phone.blank? || normalized_phone.length < 10)
        return render json: { error: "Please enter a valid 10-digit mobile number" }, status: :unprocessable_entity
      end

      account = is_email ?
              Account.find_by(email: identifier.downcase) :
              Account.find_by(phone: normalized_phone)

      if !signup
        return render json: {
          error: "Account not found. Please sign up."
        }, status: :not_found unless account
      end

      return render_blocked_account if account && blocked_actor?(account)

      if signup
        if account.present?
          return render json: {
            error: is_email ?
              "Email already registered. Please login." :
              "Phone number already registered. Please login."
          }, status: :unprocessable_entity
        end

        account = Account.create!(
          email: is_email ? identifier.downcase : nil,
          phone: is_email ? nil : normalized_phone,
          country_code: params[:country_code].presence || ENV.fetch('DEFAULT_COUNTRY_CODE', '+91'),
          status: 'pending'
        )
      end

      channel_name = is_email ? "Email" : "WhatsApp"
      OtpService.send_otp(account, channel: is_email ? "email" : "whatsapp")
      clear_otp_verify_attempts!(OTP_SCOPE, account.id)

      render json: {
        message: "6-digit OTP sent successfully via #{channel_name}",
        flow: signup ? 'signup' : 'login',
        channel: channel_name.downcase
      }, status: :ok
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
    rescue StandardError => e
      render_error(e)
    end

    def verify_otp
      identifier = params[:identifier].to_s.strip
      otp = params[:otp].to_s.strip

      if identifier.blank? || otp.blank?
        return render json: { error: "Identifier and OTP are required" }, status: :unprocessable_entity
      end

      is_email = identifier.include?('@')
      normalized_phone = is_email ? nil : identifier.gsub(/\D/, '').last(10)

      account = is_email ?
                  Account.find_by(email: identifier.downcase) :
                  Account.find_by(phone: normalized_phone)

      return render json: { error: 'Invalid or expired OTP' }, status: :unauthorized unless account

      if otp_verify_locked?(OTP_SCOPE, account.id)
        return render json: { error: "Too many wrong attempts. Please request a new OTP." }, status: :too_many_requests
      end

      unless account.otp_valid?(otp)
        record_failed_otp_attempt!(OTP_SCOPE, account.id)
        # Burn the OTP once the attempt budget is spent so it cannot be guessed further.
        account.clear_otp! if otp_verify_locked?(OTP_SCOPE, account.id)
        return render json: { error: 'Invalid or expired OTP' }, status: :unauthorized
      end

      clear_otp_verify_attempts!(OTP_SCOPE, account.id)
      return render_blocked_account if blocked_actor?(account)

      account.clear_otp!
      
      # Send login notification (only for existing accounts, not signup)
      is_signup = account.status == 'pending'

      if is_signup
        account.update(status: 'active')
        AccountMailer.signup_email(account).deliver_later if account.email.present?
        ActivityLogger.log_auth(actor: account, action: "signup", request: request)
      else
        AccountMailer.login_notification(account).deliver_later if account.email.present?
        ActivityLogger.log_auth(actor: account, action: "login", request: request)
      end
      
      token = JsonWebToken.issue_for(account)

      render json: {
        message: is_signup ? 'Signup successful' : 'Login successful',
        token: token,
        account: serialize_data(account, AccountSerializer)
      }, status: :ok
    rescue StandardError => e
      render_error(e)
    end

    def google_login
      result = GoogleTokenVerifier.verify(params[:id_token])

      return render json: { error: 'Invalid Google token' }, status: :unauthorized unless result

      account = Account.find_or_initialize_by(email: result[:email])
      is_new = account.new_record?
      return render_blocked_account if !is_new && blocked_actor?(account)

      if is_new
        generated_password = SecureRandom.urlsafe_base64(12)
        account.assign_attributes(
          email: result[:email],
          first_name: result[:first_name],
          last_name: result[:last_name],
          provider: 'google',
          provider_uid: result[:uid],
          google_signup: true,
          status: 'active',
          password: generated_password,
          password_confirmation: generated_password
        )
        account.save!
        ActivityLogger.log_auth(actor: account, action: "signup", request: request, details: { provider: "google" })
      else
        account.update!(
          provider: 'google',
          provider_uid: result[:uid],
          google_signup: true
        )
        ActivityLogger.log_auth(actor: account, action: "login", request: request, details: { provider: "google" })
      end

      token = JsonWebToken.issue_for(account)

      render json: {
        token: token,
        account: serialize_data(account, AccountSerializer)
      }
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end

    private

    def render_blocked_account
      render json: { error: BLOCKED_ACCOUNT_MESSAGE }, status: :forbidden
    end
  end
end
