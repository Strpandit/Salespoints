module Api
  class DealerSessionsController < ApplicationController
    skip_before_action :authenticate_request!, only: [:login, :forgot_password, :otp_confirmation, :reset_password]
    RESET_FLOW_TTL = 10.minutes
    FORGOT_COOLDOWN = 60.seconds

    # Per-IP ceilings: password guessing, OTP e-mail flooding and reset-OTP guessing from one source.
    rate_limit to: 10, within: 5.minutes, only: :login, name: "dealer-login", by: -> { client_ip },
               with: -> { render json: { error: "Too many login attempts. Please try again later." }, status: :too_many_requests }
    rate_limit to: 5, within: 10.minutes, only: :forgot_password, name: "dealer-forgot", by: -> { client_ip },
               with: -> { render json: { error: "Too many requests. Please try again later." }, status: :too_many_requests }
    rate_limit to: 20, within: 10.minutes, only: [:otp_confirmation, :reset_password], name: "dealer-reset", by: -> { client_ip },
               with: -> { render json: { error: "Too many attempts. Please try again later." }, status: :too_many_requests }

    def login
      dealer = Dealer.active.find_by(email: params[:email]&.downcase) || Dealer.find_by(phone: params[:phone]&.gsub(/\D/, ''))

      return unauthorized("Invalid credentials") unless dealer&.authenticate(params[:password]) && dealer.active?

      token = JsonWebToken.issue_for(dealer)
      ActivityLogger.log_auth(actor: dealer, action: "login", request: request)

      render json: {
        token: token,
        dealer: serialize_data(dealer, DealerSerializer),
        message: "Logged in successfully"
      }, status: :ok
    end

    def change_password
      dealer = current_dealer

      unless dealer.authenticate(params[:current_password])
        return render json:{error:"Incorrect password"}, status: :unauthorized
      end

      if dealer.update(
        password: params[:new_password],
        password_confirmation: params[:confirm_password]
      )
        ActivityLogger.log_auth(actor: dealer, action: "change_password", request: request)
        # Sign out every other session; hand back a fresh token so this device stays signed in.
        dealer.revoke_tokens!
        render json:{message:"Password changed", token: JsonWebToken.issue_for(dealer)}, status: :ok
      else
        render json:{error: dealer.errors.full_messages}, status: :unprocessable_entity
      end
    end

    def forgot_password
      dealer = Dealer.active.find_by(email: params[:email]&.downcase) || Dealer.active.find_by(phone: params[:phone]&.gsub(/\D/, ''))
      # Same answer whether or not the dealer exists, so this cannot be used to discover accounts.
      # The placeholder id never matches a real dealer, so OTP verification just fails for it.
      unless dealer&.email.present?
        return render json: { message: "OTP sent successfully", id: 900_000_000 + SecureRandom.random_number(99_999_999) }, status: :ok
      end

      # Inside the cooldown keep the OTP already sent (a flood of requests must not keep
      # invalidating the owner's code or spam their inbox).
      if dealer.otp_sent_at&.after?(FORGOT_COOLDOWN.ago)
        return render json: { message: "OTP sent successfully", id: dealer.id }, status: :ok
      end

      dealer.update!(otp_pin: SecureRandom.random_number(1000..9999).to_s, otp_sent_at: Time.current)
      Rails.cache.delete(reset_flow_cache_key(dealer.id))
      DealerAuthMailer.forgot_password_otp(dealer).deliver_later if dealer.email.present?
      ActivityLogger.log_auth(actor: dealer, action: "forgot_password_otp_sent", request: request)
      render json: { message: "OTP sent successfully", id: dealer.id }, status: :ok
    end

    def otp_confirmation
      dealer = Dealer.active.find_by(id: params[:id])
      return unauthorized("Invalid OTP") unless dealer
      return unauthorized("Too many attempts. Please request a new OTP.") if otp_verify_locked?("dealer_reset", dealer.id)

      unless dealer.otp_valid?(params[:otp].to_s)
        record_failed_otp_attempt!("dealer_reset", dealer.id)
        return unauthorized("Invalid OTP")
      end
      clear_otp_verify_attempts!("dealer_reset", dealer.id)

      reset_token = SecureRandom.hex(24)
      Rails.cache.write(reset_flow_cache_key(dealer.id), reset_token, expires_in: RESET_FLOW_TTL)
      ActivityLogger.log_auth(actor: dealer, action: "otp_verified", request: request)

      render json: { message: "OTP verified successfully", reset_token: reset_token }, status: :ok
    end

    def reset_password
      dealer = Dealer.active.find_by(id: params[:id])
      return unauthorized("Invalid OTP") unless dealer
      reset_token = params[:reset_token].to_s
      cached_token = Rails.cache.read(reset_flow_cache_key(dealer.id)).to_s
      if reset_token.blank? || cached_token.blank? || !ActiveSupport::SecurityUtils.secure_compare(cached_token, reset_token)
        return unauthorized("Reset session expired. Verify OTP again.")
      end

      if dealer.update(password: params[:password], password_confirmation: params[:password_confirmation])
        dealer.update(otp_pin: nil, otp_sent_at: nil)
        dealer.revoke_tokens!
        Rails.cache.delete(reset_flow_cache_key(dealer.id))
        DealerAuthMailer.password_reset_confirmation(dealer).deliver_later if dealer.email.present?
        ActivityLogger.log_auth(actor: dealer, action: "reset_password", request: request)
        render json: { message: "Password reset successfully" }, status: :ok
      else
        render json: { error: dealer.errors.full_messages }, status: :unprocessable_entity
      end
    end

    private

    def unauthorized(msg)
      render json: { error: msg }, status: :unauthorized and return
    end

    def reset_flow_cache_key(dealer_id)
      "dealer_password_reset_verified:#{dealer_id}"
    end
  end
end
