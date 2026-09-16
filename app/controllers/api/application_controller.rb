module Api
  class ApplicationController < ActionController::API
    before_action :authenticate_request!

    attr_reader :current_user, :current_user_type

    private

    def authenticate_request!
      token = request.headers['Authorization']&.split(' ')&.last
      return unauthorized('Missing token') unless token

      payload = JsonWebToken.decode(token)
      return unauthorized('Invalid token') unless payload

      @current_user_type = payload[:user_type]
      @current_user = find_user(payload)

      return unauthorized('Invalid token') unless @current_user
    rescue JWT::ExpiredSignature
      unauthorized('Token has expired')
    rescue JWT::DecodeError
      unauthorized('Invalid token')
    end

    def find_user(payload)
      case payload[:user_type]
      when 'Account'
        Account.find_by(id: payload[:user_id])
      when 'Dealer'
        Dealer.find_by(id: payload[:user_id])
      when 'AdminUser'
        AdminUser.find_by(id: payload[:user_id])
      else
        nil
      end
    end

    def unauthorized(message)
      render json: { error: message }, status: :unauthorized and return
    end

    def current_admin
      current_user if current_user_type == 'AdminUser'
    end

    def current_dealer
      current_user if current_user_type == 'Dealer'
    end

    def current_account
      current_user if current_user_type.to_s.strip == 'Account'
    end

    def serialize_resource(resource, serializer, options = {})
      { data: serializer.render(resource, viewer_context.merge(options)) }
    end

    def viewer_context
      if current_admin
        { viewer: :admin }
      elsif current_dealer
        { viewer: :dealer, viewer_id: current_dealer.id }
      elsif current_account
        { viewer: :customer, viewer_id: current_account.id }
      else
        { viewer: :public }
      end
    end

    def serialize_data(resource, serializer, options = {})
      serialize_resource(resource, serializer, options)[:data]
    end

    OTP_VERIFY_MAX_ATTEMPTS = 3
    OTP_VERIFY_LOCKOUT_WINDOW = 10.minutes

    def otp_verify_locked?(scope, id)
      Rails.cache.read(otp_verify_attempts_key(scope, id)).to_i >= OTP_VERIFY_MAX_ATTEMPTS
    end

    def record_failed_otp_attempt!(scope, id)
      key = otp_verify_attempts_key(scope, id)
      Rails.cache.write(key, Rails.cache.read(key).to_i + 1, expires_in: OTP_VERIFY_LOCKOUT_WINDOW)
    end

    def clear_otp_verify_attempts!(scope, id)
      Rails.cache.delete(otp_verify_attempts_key(scope, id))
    end

    def otp_verify_attempts_key(scope, id)
      "otp_verify_attempts:#{scope}:#{id}"
    end
    LEAKY_EXCEPTION_CLASSES = [
      ActiveRecord::StatementInvalid,
      ActiveRecord::RecordNotFound,
      NoMethodError,
      TypeError,
      NameError,
      JSON::ParserError
    ].freeze

    def render_error(e, status: :unprocessable_entity)
      if leaky_exception?(e)
        Rails.logger.error("[#{controller_name}##{action_name}] #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
        render json: { error: "Something went wrong. Please try again." }, status: :internal_server_error
      else
        render json: { error: e.message }, status: status
      end
    end

    def leaky_exception?(e)
      LEAKY_EXCEPTION_CLASSES.any? { |klass| e.is_a?(klass) } ||
        e.class.name.to_s.start_with?("PG::", "Net::", "Errno::")
    end
  end
end
