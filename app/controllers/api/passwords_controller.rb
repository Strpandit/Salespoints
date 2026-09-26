module Api
  class PasswordsController < ApplicationController
    def create
      account = Account.find_by(email: params[:email]&.downcase)
      return render json: { error: 'Not found' }, status: :not_found unless account

      token = SecureRandom.urlsafe_base64
      account.update!(reset_password_token: token, reset_password_sent_at: Time.current)

      AccountMailer.set_password(account).deliver_later
      ActivityLogger.log_auth(actor: account, action: "forgot_password_link_sent", request: request)
      render json: { message: 'Reset link sent' }
    end

    def update
      account = Account.find_by(reset_password_token: params[:token])
      return render json: { error: 'Invalid token' }, status: :unauthorized unless account

      unless params[:password] == params[:password_confirmation]
        return render json: { error: 'Passwords do not match' }, status: :unprocessable_entity
      end

      account.update!(
        password: params[:password],
        password_confirmation: params[:password_confirmation],
        reset_password_token: nil,
        status: 'active'
      )

      ActivityLogger.log_auth(actor: account, action: "reset_password", request: request)
      render json: { message: 'Password set successfully' }
    end
  end
end
