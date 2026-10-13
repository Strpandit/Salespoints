module PasswordPolicy
  extend ActiveSupport::Concern

  MIN_PASSWORD_LENGTH = 8

  private

  def password_policy_error(password, confirmation = nil)
    password = password.to_s
    return "Password is required" if password.blank?
    return "Password must be at least #{MIN_PASSWORD_LENGTH} characters" if password.length < MIN_PASSWORD_LENGTH
    return "Password and confirmation do not match" if !confirmation.nil? && password != confirmation.to_s

    nil
  end

  def render_password_policy_error(message)
    render json: { error: message }, status: :unprocessable_entity
  end
end
