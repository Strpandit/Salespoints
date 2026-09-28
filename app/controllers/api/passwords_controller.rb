module Api
  # Customer "forgot password": POST /api/password emails a reset link,
  # POST /api/set_password sets the new password from that link.
  class PasswordsController < ApplicationController
    RESET_TOKEN_TTL = 30.minutes
    RESEND_COOLDOWN = 1.minute
    GENERIC_MESSAGE = "If an account exists for this email, a password reset link has been sent.".freeze

    # The whole point is to help logged-out customers.
    skip_before_action :authenticate_request!

    rate_limit to: 10, within: 10.minutes, only: :create, name: "password-reset", by: -> { client_ip },
               with: -> { render json: { error: "Too many requests. Please try again later." }, status: :too_many_requests }

    def create
      email = params[:email].to_s.strip.downcase
      return render json: { error: "Please enter your registered email" }, status: :unprocessable_entity if email.blank?

      account = Account.where(deleted_at: nil).find_by(email: email)
      # Same answer whether or not the email exists, so this can't be used to discover accounts.
      return render json: { message: GENERIC_MESSAGE } unless account
      # Quietly skip resends inside the cooldown so the link can't be used to flood an inbox.
      return render json: { message: GENERIC_MESSAGE } if account.reset_password_sent_at&.after?(RESEND_COOLDOWN.ago)

      account.update_columns(
        reset_password_token: SecureRandom.urlsafe_base64(32),
        reset_password_sent_at: Time.current,
        updated_at: Time.current
      )
      AccountMailer.set_password(account).deliver_later
      ActivityLogger.log_auth(actor: account, action: "forgot_password_link_sent", request: request)
      render json: { message: GENERIC_MESSAGE }
    end

    def update
      token = params[:token].to_s
      account = token.present? ? Account.where(deleted_at: nil).find_by(reset_password_token: token) : nil

      if account.nil? || account.reset_password_sent_at.blank? || account.reset_password_sent_at < RESET_TOKEN_TTL.ago
        return render json: { error: "This reset link is invalid or has expired. Please request a new one." }, status: :unauthorized
      end

      password = params[:password].to_s
      unless password == params[:password_confirmation].to_s
        return render json: { error: "Passwords do not match" }, status: :unprocessable_entity
      end
      return render json: { error: "Password must be at least 8 characters" }, status: :unprocessable_entity if password.length < 8

      attrs = { password: password, password_confirmation: password, reset_password_token: nil, reset_password_sent_at: nil }
      # Only finish an incomplete signup; never re-activate a blocked/banned account.
      attrs[:status] = "active" if account.pending?

      if account.update(attrs)
        ActivityLogger.log_auth(actor: account, action: "reset_password", request: request)
        render json: { message: "Password updated. You can now log in with your new password." }
      else
        render json: { error: account.errors.full_messages.first || "Could not update password" }, status: :unprocessable_entity
      end
    end
  end
end
