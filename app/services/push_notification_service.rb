require "openssl"
require "net/http"
require "uri"
require "json"

class PushNotificationService
  EXPO_PUSH_URL = "https://exp.host/--/api/v2/push/send".freeze
  GOOGLE_OAUTH_TOKEN_URL = "https://oauth2.googleapis.com/token".freeze
  FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging".freeze
  RETRYABLE_STATUS_CODES = [429, 500, 502, 503, 504].freeze
  TRANSIENT_ERRORS = [Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, Errno::ECONNREFUSED, SocketError, OpenSSL::SSL::SSLError].freeze
  INTERNAL_PAYLOAD_KEYS = %w[delivery_channels visible_in_app notifiable_type notifiable_id].freeze
  ORDER_RING_KINDS = %w[b2c_order_request b2b_order_request b2c_order_broadcast b2b_order_broadcast].freeze
  INFO_RING_KINDS = %w[new_wholesaler_post offer_mart_order_placed].freeze
  RING_KINDS = (ORDER_RING_KINDS + INFO_RING_KINDS).freeze
  RING_DROPPED_KEYS = %w[items item_ids params].freeze
  FCM_DATA_BUDGET = 3200
  ESSENTIAL_DATA_KEYS = %w[notification_type notification_id screen role order_id params wholesaler_post_id product_id deal_id].freeze
  RING_TTL = "600s".freeze

  def deliver(notification, tokens: nil)
    channels = notification.delivery_channels
    return [] if channels.key?("push") && channels["push"] == false

    subscriptions = PushSubscription.where(subscriber: notification.receiver)
    subscriptions = subscriptions.where(token: tokens) if tokens.present?
    ring_capable = subscriptions.where(supports_ring: true).distinct.pluck(:token).to_set
    tokens = subscriptions.distinct.pluck(:token)
    return [] if tokens.empty?
    ring_kind = RING_KINDS.include?(notification.notification_type.to_s)
    # A ring can arrive late (queue lag, retry) after the request was already taken or closed.
    ring_open = !ring_kind || ring_request_open?(notification)

    creds = firebase_credentials
    if creds.blank? && tokens.any? { |token| !expo_token?(token) }
      Rails.logger.error("[PushNotificationService] No Firebase credentials configured; FCM tokens skipped for notification=#{notification.id}")
    end

    data_payload = build_data_payload(notification)
    retryable = []

    tokens.each do |token|
      next if ring_kind && !ring_open && ring_capable.include?(token)

      result =
        if expo_token?(token)
          send_expo_push(token, notification, data_payload)
        elsif creds.present?
          send_fcm_v1_push(token, notification, data_payload, creds, ring: ring_kind && ring_capable.include?(token))
        else
          :retry
        end

      case result
      when :stale then PushSubscription.where(token: token).destroy_all
      when :retry then retryable << token
      end
    end

    retryable
  end

  # Ring requests keep ringing on a dealer's phone until answered. Once the order is taken by someone else (or
  # closes), tell every other dealer who was alerted to stop: a data-only push the app turns into "cancel that
  # ringing notification". Best effort: a failure here must never affect the order flow.
  def self.cancel_ring(order, except_dealer_id: nil)
    new.cancel_ring(order, except_dealer_id: except_dealer_id)
  rescue StandardError => e
    Rails.logger.warn("[PushNotificationService] cancel_ring failed for #{order.class.name}##{order&.id}: #{e.message}")
    []
  end

  def cancel_ring(order, except_dealer_id: nil)
    return [] if order.blank?

    alerts = Notification.where(receiver_type: "Dealer", notifiable_type: order.class.name, notifiable_id: order.id,
                                notification_type: RING_KINDS)
    alerts = alerts.where.not(receiver_id: except_dealer_id) if except_dealer_id.present?
    dealer_ids = alerts.distinct.pluck(:receiver_id)
    return [] if dealer_ids.empty?

    tokens = PushSubscription.where(subscriber_type: "Dealer", subscriber_id: dealer_ids, supports_ring: true).distinct.pluck(:token)
    tokens = tokens.reject { |token| expo_token?(token) }
    return [] if tokens.empty?

    creds = firebase_credentials
    return [] if creds.blank?

    access_token = fetch_oauth_access_token(creds)
    return [] if access_token.blank?

    data = {
      "ring_cancel" => "1",
      "order_id" => order.id.to_s,
      "order_type" => order.is_a?(B2bOrder) ? "b2b" : "retail"
    }

    tokens.each do |token|
      HTTParty.post(
        "https://fcm.googleapis.com/v1/projects/#{creds['project_id']}/messages:send",
        headers: { "Authorization" => "Bearer #{access_token}", "Content-Type" => "application/json; UTF-8" },
        body: { message: { token: token, data: data, android: { priority: "high", ttl: "120s" } } }.to_json,
        timeout: 10
      )
    rescue StandardError => e
      Rails.logger.warn("[PushNotificationService] cancel_ring push failed ...#{token.last(6)}: #{e.message}")
    end
    tokens
  end

  private

  # Order requests only ring while someone can still answer them. Bulk-deal and Offer Mart alerts are
  # informational and always ring.
  def ring_request_open?(notification)
    return true unless ORDER_RING_KINDS.include?(notification.notification_type.to_s)

    order = notification.notifiable
    case order
    when Order
      order.status.to_s == "pending" && order.seller_dealer_id.blank?
    when B2bOrder
      order.request_status.to_s == "pending_request"
    else
      true
    end
  rescue StandardError => e
    Rails.logger.warn("[PushNotificationService] ring_request_open? check failed for notification=#{notification.id}: #{e.message}")
    true
  end

  def expo_token?(token)
    token.start_with?("ExponentPushToken[") || token.start_with?("ExpoPushToken[")
  end

  def determine_channel_id(notif_type)
    type = notif_type.to_s
    if type.include?("broadcast") || type.include?("expiring") || type.include?("security")
      "orders_urgent"
    elsif type.include?("order") || type.include?("payout") || type.include?("replacement") || type.include?("payment")
      "orders_standard"
    else
      "updates_default"
    end
  end

  def determine_target_screen(notification)
    type = notification.notification_type.to_s
    notifiable = notification.notifiable
    payload = notification.payload || {}

    return payload["screen"] if payload["screen"].present?

    if notifiable.is_a?(Order) || payload["order_id"].present? || type.include?("order")
      if notification.receiver_type == "Dealer"
        "DealerOrders"
      else
        "CustomerOrderDetails"
      end
    elsif type.include?("wholesaler") || payload["wholesaler_post_id"].present?
      "DealerWholesalerFeed"
    elsif type.include?("payout") || type.include?("settlement")
      "DealerPayments"
    elsif type.include?("b2b")
      "DealerB2BProducts"
    elsif payload["product_id"].present?
      "ProductDetails"
    elsif payload["deal_id"].present?
      "OfferMartDetails"
    elsif type.include?("ticket") || type.include?("support")
      "Support"
    else
      "Notifications"
    end
  end

  def build_data_payload(notification)
    notif_type = notification.notification_type.to_s
    notifiable = notification.notifiable
    payload = notification.payload || {}
    screen = determine_target_screen(notification)

    base = {
      "notification_type" => notif_type,
      "notification_id" => notification.id.to_s,
      "screen" => screen,
      "role" => (notification.receiver_type == "Dealer" ? "dealer" : "customer")
    }

    if order_notifiable?(notifiable)
      base["order_id"] = notifiable.id.to_s
      base["params"] = { orderId: notifiable.id, role: base["role"] }.to_json
    elsif payload["order_id"].present?
      base["order_id"] = payload["order_id"].to_s
      base["params"] = { orderId: payload["order_id"], role: base["role"] }.to_json
    elsif payload["product_id"].present?
      base["product_id"] = payload["product_id"].to_s
      base["params"] = { idOrSlug: payload["product_id"] }.to_json
    elsif payload["deal_id"].present?
      base["deal_id"] = payload["deal_id"].to_s
      base["params"] = { id: payload["deal_id"] }.to_json
    elsif payload["wholesaler_post_id"].present?
      base["wholesaler_post_id"] = payload["wholesaler_post_id"].to_s
      base["params"] = { postId: payload["wholesaler_post_id"] }.to_json
    end

    data = base.merge(flat_string_data(payload.except(*INTERNAL_PAYLOAD_KEYS)))

    if order_notifiable?(notifiable)
      data["order_number"] = payload["order_id"].to_s if payload["order_id"].present? && payload["order_id"].to_s != notifiable.id.to_s
      data["order_id"] = notifiable.id.to_s
      data["order_type"] = notifiable.is_a?(B2bOrder) ? "b2b" : "retail"
      data["params"] = { orderId: notifiable.id, role: base["role"], orderType: data["order_type"] }.to_json
    end

    fit_fcm_data_limit(data)
  end

  def order_notifiable?(notifiable)
    notifiable.is_a?(Order) || notifiable.is_a?(B2bOrder)
  end

  def fit_fcm_data_limit(data)
    return data if data.to_json.bytesize <= FCM_DATA_BUDGET

    data = data.dup
    data.keys.sort_by { |key| -data[key].to_s.bytesize }.each do |key|
      break if data.to_json.bytesize <= FCM_DATA_BUDGET
      next if ESSENTIAL_DATA_KEYS.include?(key)

      data.delete(key)
    end
    data
  end

  def ring_data(notification, data_payload)
    type = notification.notification_type.to_s
    notifiable = notification.notifiable
    payload = notification.payload || {}
    data = data_payload.except(*RING_DROPPED_KEYS)
    data["order_number"] = payload["order_id"].to_s if payload["order_id"].present?

    if ORDER_RING_KINDS.include?(type)
      data["alert_kind"] = "order"
      data["order_type"] = type.start_with?("b2b") ? "b2b" : "retail"
      data["order_id"] = notifiable.id.to_s if notifiable.respond_to?(:id)
      data["screen"] = "DealerOrders"
      data["params"] = { orderId: notifiable.id, role: "dealer" }.to_json if notifiable.respond_to?(:id)
    elsif type == "new_wholesaler_post"
      post_id = (payload["wholesaler_post_id"] || notifiable&.id).to_s
      data["alert_kind"] = "wholesaler"
      data["screen"] = "DealerWholesalerFeed"
      data["params"] = { postId: post_id }.to_json
    else
      data["alert_kind"] = "offer_mart"
      data["order_type"] = "retail"
      data["screen"] = "DealerOrders"
      if notifiable.respond_to?(:id)
        data["order_id"] = notifiable.id.to_s
        data["params"] = { orderId: notifiable.id, role: "dealer" }.to_json
      end
    end
    data
  end

  def fcm_message(device_token, notification, data_payload, ring)
    title = notification.title.to_s.truncate(120)
    body = notification.body.to_s.truncate(240)

    if ring
      return {
        message: {
          token: device_token,
          data: ring_data(notification, data_payload).merge("title" => title, "body" => body, "ring" => "1"),
          android: { priority: "high", ttl: RING_TTL }
        }
      }
    end

    {
      message: {
        token: device_token,
        notification: { title: title, body: body },
        data: data_payload,
        android: {
          priority: "high",
          notification: {
            channel_id: determine_channel_id(notification.notification_type),
            sound: "default"
          }
        },
        apns: {
          payload: {
            aps: {
              sound: "default",
              badge: 1
            }
          }
        }
      }
    }
  end

  def send_fcm_v1_push(device_token, notification, data_payload, creds, ring: false, refreshed: false)
    access_token = fetch_oauth_access_token(creds)
    return :retry if access_token.blank?

    message = fcm_message(device_token, notification, data_payload, ring)

    response = HTTParty.post(
      "https://fcm.googleapis.com/v1/projects/#{creds['project_id']}/messages:send",
      headers: {
        "Authorization" => "Bearer #{access_token}",
        "Content-Type" => "application/json; UTF-8"
      },
      body: message.to_json,
      timeout: 10
    )

    if response.code == 401 && !refreshed
      Rails.cache.delete(oauth_cache_key(creds)) rescue nil
      return send_fcm_v1_push(device_token, notification, data_payload, creds, ring: ring, refreshed: true)
    end

    classify_fcm_response(response, notification, device_token)
  rescue *TRANSIENT_ERRORS => e
    Rails.logger.warn("[PushNotificationService] FCM v1 network error for notification=#{notification.id}: #{e.class} #{e.message}")
    :retry
  rescue StandardError => e
    Rails.logger.warn("[PushNotificationService] FCM v1 deliver failed for notification=#{notification.id}: #{e.message}")
    :failed
  end

  def classify_fcm_response(response, notification, device_token)
    code = response.code.to_i
    return :ok if code.between?(200, 299)

    error = fcm_error(response)
    message = error["message"].to_s
    error_codes = Array(error["details"]).map { |detail| detail["errorCode"] if detail.is_a?(Hash) }.compact

    if error_codes.include?("UNREGISTERED") || error_codes.include?("SENDER_ID_MISMATCH") ||
       (code == 400 && message.include?("registration token")) || code == 404
      Rails.logger.info("[PushNotificationService] Removing dead token ...#{device_token.last(6)} (notification=#{notification.id})")
      return :stale
    end

    Rails.logger.warn("[PushNotificationService] FCM #{code} #{error['status']} for notification=#{notification.id} token=...#{device_token.last(6)}: #{message}")
    RETRYABLE_STATUS_CODES.include?(code) ? :retry : :failed
  end

  def fcm_error(response)
    parsed = JSON.parse(response.body.to_s)
    parsed.is_a?(Hash) && parsed["error"].is_a?(Hash) ? parsed["error"] : {}
  rescue JSON::ParserError
    {}
  end

  def send_expo_push(expo_token, notification, data_payload)
    channel_id = determine_channel_id(notification.notification_type)

    body = {
      to: expo_token,
      sound: "default",
      priority: "high",
      channelId: channel_id,
      title: notification.title.to_s.truncate(120),
      body: notification.body.to_s.truncate(240),
      data: data_payload
    }

    HTTParty.post(
      EXPO_PUSH_URL,
      headers: {
        "Accept" => "application/json",
        "Accept-Encoding" => "gzip, deflate",
        "Content-Type" => "application/json"
      },
      body: body.to_json,
      timeout: 10
    )
    :ok
  rescue StandardError => e
    Rails.logger.warn("[PushNotificationService] Expo deliver failed: #{e.message}")
    :failed
  end

  def firebase_credentials
    if ENV["FIREBASE_SERVICE_ACCOUNT_JSON"].present?
      begin
        return JSON.parse(ENV["FIREBASE_SERVICE_ACCOUNT_JSON"])
      rescue StandardError => e
        Rails.logger.error("[PushNotificationService] Failed to parse FIREBASE_SERVICE_ACCOUNT_JSON: #{e.message}")
      end
    end

    local_path = Rails.root.join("config", "firebase_credentials.json")
    if File.exist?(local_path)
      begin
        return JSON.parse(File.read(local_path))
      rescue StandardError => e
        Rails.logger.error("[PushNotificationService] Failed to read #{local_path}: #{e.message}")
      end
    end

    nil
  end

  def oauth_cache_key(creds)
    "fcm_v1_access_token_#{creds['project_id']}"
  end

  def fetch_oauth_access_token(creds)
    cache_key = oauth_cache_key(creds)
    cached = Rails.cache.read(cache_key) rescue nil
    return cached if cached.present?

    now = Time.current.to_i
    jwt_claim = {
      iss: creds["client_email"],
      scope: FCM_SCOPE,
      aud: GOOGLE_OAUTH_TOKEN_URL,
      iat: now,
      exp: now + 3600
    }

    rsa_private = OpenSSL::PKey::RSA.new(creds["private_key"])
    signed_jwt = JWT.encode(jwt_claim, rsa_private, "RS256")

    uri = URI.parse(GOOGLE_OAUTH_TOKEN_URL)
    req = Net::HTTP::Post.new(uri)
    req.set_form_data(
      "grant_type" => "urn:ietf:params:oauth:grant-type:jwt-bearer",
      "assertion" => signed_jwt
    )

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 5
    http.read_timeout = 10
    res = http.request(req)

    if res.is_a?(Net::HTTPSuccess)
      data = JSON.parse(res.body)
      token = data["access_token"]
      expires_in = data["expires_in"] || 3600
      Rails.cache.write(cache_key, token, expires_in: (expires_in.to_i - 300).seconds) rescue nil
      token
    else
      Rails.logger.error("[PushNotificationService] OAuth2 token exchange failed: #{res.body}")
      nil
    end
  rescue StandardError => e
    Rails.logger.error("[PushNotificationService] fetch_oauth_access_token error: #{e.message}")
    nil
  end

  def reserved_data_key?(key)
    key.empty? || %w[from notification message_type].include?(key) || key.start_with?("google", "gcm")
  end

  def flat_string_data(payload)
    out = {}
    (payload || {}).each do |k, v|
      key = k.to_s
      next if reserved_data_key?(key)

      out[key] = v.is_a?(Hash) || v.is_a?(Array) ? v.to_json : v.to_s
    end
    out
  end
end
