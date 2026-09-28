module Api
  class ApplicationController < ActionController::API
    include ActivityTrackable

    before_action :authenticate_request!

    attr_reader :current_user, :current_user_type

    private

    # Statuses that lose API access immediately, even with a token issued before the change.
    # (Account "pending" and Dealer "pending" are left alone: pending accounts can hold a
    # Google-login token, and login endpoints already keep non-active dealers out.)
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

    # Real visitor IP for per-IP rate limits. Behind Cloudflare every request reaches us from a
    # Cloudflare edge address, so prefer the header it sets; otherwise Rails' proxy-aware remote_ip.
    def client_ip
      request.headers["CF-Connecting-IP"].presence || request.remote_ip
    end

    def bearer_token
      request.headers["Authorization"]&.split(" ")&.last.presence
    end

    # Returns [user, user_type, nil] for a usable session, otherwise [nil, nil, reason].
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

    # `code` lets web/mobile tell a dead session apart from other 401s (wrong password, bad OTP).
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
