module Api
  class ApplicationController < ActionController::API
    include ActivityTrackable

    before_action :authenticate_request!
    before_action :sanitize_paging_params

    rescue_from ActionController::ParameterMissing do |e|
      render json: { error: "Missing required parameter: #{e.param}" }, status: :bad_request
    end
    rescue_from ActionController::BadRequest, ActionDispatch::Http::Parameters::ParseError do |_e|
      render json: { error: "Invalid request" }, status: :bad_request
    end
    rescue_from ActiveRecord::RecordNotFound do |_e|
      render json: { error: "Record not found" }, status: :not_found
    end
    rescue_from ActiveRecord::RecordInvalid do |e|
      render json: { error: e.record.errors.full_messages.to_sentence.presence || "Validation failed" }, status: :unprocessable_entity
    end
    rescue_from NoMethodError do |e|
      raise e unless e.name == :permit && !e.receiver.is_a?(ActionController::Parameters)

      render json: { error: "Invalid request body" }, status: :bad_request
    end
    rescue_from ActiveModel::RangeError, RangeError do |_e|
      render json: { error: "Parameter out of range" }, status: :unprocessable_entity
    end

    attr_reader :current_user, :current_user_type

    private

    def sanitize_paging_params
      %i[page per_page].each do |key|
        next unless params.key?(key)

        value = params[key]
        if value.is_a?(String) || value.is_a?(Numeric)
          digits = value.to_s
          params[key] = (key == :page ? "1000000" : "500") if digits.match?(/\A\d{10,}\z/)
        else
          params.delete(key)
        end
      end

      params.delete(:per_page) if !strict_per_page? && params.key?(:per_page) && params[:per_page].to_s.match?(/\A-?\d+\z/) && params[:per_page].to_i <= 0

      STRING_PARAM_KEYS.each do |key|
        params.delete(key) if params.key?(key) && !(params[key].is_a?(String) || params[key].is_a?(Numeric) || params[key].nil?)
      end
    end
    def strict_per_page?
      false
    end

    STRING_PARAM_KEYS = %i[search q query email identifier pincode token reason brands ratings
                           payment_reference platform otp recipient_email phone password current_password new_password
                           confirm_password password_confirmation].freeze

    BLOCKED_STATUSES = {
      "Account" => %w[banned inactive],
      "Dealer" => %w[banned inactive rejected],
      "AdminUser" => %w[inactive]
    }.freeze
    BLOCKED_ACCOUNT_MESSAGE = "Your account has been blocked. Please contact support.".freeze

    def authenticate_request!
      token = bearer_token
      return render_session_invalid("Missing token") unless token

      user, user_type, failure = resolve_session(token)
      return render_session_invalid(failure) if failure

      @current_user_type = user_type
      @current_user = user
    end

    def client_ip
      request.headers["CF-Connecting-IP"].presence || request.remote_ip
    end

    def bearer_token
      request.headers["Authorization"]&.split(" ")&.last.presence
    end

    def resolve_session(token)
      payload = JsonWebToken.decode(token)
      user = find_user(payload)
      return [nil, nil, "Invalid token"] unless user
      return [nil, nil, "Session expired. Please log in again."] unless JsonWebToken.current_version?(payload, user)
      return [nil, nil, BLOCKED_ACCOUNT_MESSAGE] if blocked_actor?(user)

      [user, payload[:user_type], nil]
    rescue JWT::ExpiredSignature
      [nil, nil, "Token has expired"]
    rescue JWT::DecodeError
      [nil, nil, "Invalid token"]
    end

    def blocked_actor?(user)
      BLOCKED_STATUSES.fetch(user.class.name, []).include?(user.status.to_s)
    end

    def render_session_invalid(message)
      render json: { error: message, code: "session_invalid" }, status: :unauthorized
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
    # Customers type OTPs on phones, so they get a slightly larger budget than staff flows.
    OTP_SCOPE_MAX_ATTEMPTS = { "customer_login" => 5, "delivery_otp" => 5 }.freeze

    def otp_verify_locked?(scope, id)
      Rails.cache.read(otp_verify_attempts_key(scope, id)).to_i >= OTP_SCOPE_MAX_ATTEMPTS.fetch(scope, OTP_VERIFY_MAX_ATTEMPTS)
    end

    def record_failed_otp_attempt!(scope, id)
      key = otp_verify_attempts_key(scope, id)
      # increment is atomic per store, so parallel guesses cannot slip past the limit.
      Rails.cache.increment(key, 1, expires_in: OTP_VERIFY_LOCKOUT_WINDOW) ||
        Rails.cache.write(key, 1, expires_in: OTP_VERIFY_LOCKOUT_WINDOW)
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
      JSON::ParserError,
      ZeroDivisionError,
      FloatDomainError,
      SocketError,
      Timeout::Error,
      OpenSSL::OpenSSLError
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
        e.class.name.to_s.start_with?("PG::", "Net::", "Errno::", "Aws::", "Seahorse::", "HTTParty::", "JWT::")
    end
  end
end
