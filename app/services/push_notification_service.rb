require "openssl"
require "net/http"
require "uri"
require "json"

class PushNotificationService
  FCM_LEGACY_URL = "https://fcm.googleapis.com/fcm/send".freeze
  EXPO_PUSH_URL = "https://exp.host/--/api/v2/push/send".freeze
  GOOGLE_OAUTH_TOKEN_URL = "https://oauth2.googleapis.com/token".freeze
  FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging".freeze

  def deliver(notification)
    channels = notification.delivery_channels
    return if channels.key?("push") && channels["push"] == false

    tokens = PushSubscription.where(subscriber: notification.receiver).distinct.pluck(:token)
    return if tokens.empty?

    creds = firebase_credentials
    server_key = ENV["FCM_SERVER_KEY"].to_s

    tokens.each do |token|
      if token.start_with?("ExponentPushToken[") || token.start_with?("ExpoPushToken[")
        send_expo_push(token, notification)
      elsif creds.present?
        send_fcm_v1_push(token, notification, creds)
      elsif server_key.present?
        send_fcm_legacy_push(token, notification, server_key)
      end
    end
  end

  private

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
        type.include?("broadcast") ? "DealerOrders" : "DealerOrderDetails"
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

    if notifiable.is_a?(Order)
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

    base.merge(flat_string_data(payload))
  end

  def send_fcm_v1_push(device_token, notification, creds)
    access_token = fetch_oauth_access_token(creds)
    return send_fcm_legacy_push(device_token, notification, ENV["FCM_SERVER_KEY"]) if access_token.blank? && ENV["FCM_SERVER_KEY"].present?
    return if access_token.blank?

    project_id = creds["project_id"]
    endpoint = "https://fcm.googleapis.com/v1/projects/#{project_id}/messages:send"
    channel_id = determine_channel_id(notification.notification_type)
    data_payload = build_data_payload(notification)

    message = {
      message: {
        token: device_token,
        notification: {
          title: notification.title.to_s.truncate(120),
          body: notification.body.to_s.truncate(240)
        },
        data: data_payload,
        android: {
          priority: "high",
          notification: {
            channel_id: channel_id,
            sound: "default",
            click_action: "FLUTTER_NOTIFICATION_CLICK"
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

    HTTParty.post(
      endpoint,
      headers: {
        "Authorization" => "Bearer #{access_token}",
        "Content-Type" => "application/json; UTF-8"
      },
      body: message.to_json,
      timeout: 10
    )
  rescue StandardError => e
    Rails.logger.warn("[PushNotificationService] FCM v1 deliver failed: #{e.message}")
  end

  def send_fcm_legacy_push(device_token, notification, server_key)
    notif_type = notification.notification_type.to_s
    channel_id = determine_channel_id(notif_type)
    data_payload = build_data_payload(notification)

    body = {
      to: device_token,
      priority: "high",
      content_available: true,
      notification: {
        title: notification.title.to_s.truncate(120),
        body: notification.body.to_s.truncate(240),
        sound: "default",
        android_channel_id: channel_id,
        click_action: "FLUTTER_NOTIFICATION_CLICK"
      },
      data: data_payload
    }

    HTTParty.post(
      FCM_LEGACY_URL,
      headers: {
        "Authorization" => "key=#{server_key}",
        "Content-Type" => "application/json"
      },
      body: body.to_json,
      timeout: 10
    )
  rescue StandardError => e
    Rails.logger.warn("[PushNotificationService] FCM legacy deliver failed: #{e.message}")
  end

  def send_expo_push(expo_token, notification)
    notif_type = notification.notification_type.to_s
    channel_id = determine_channel_id(notif_type)
    data_payload = build_data_payload(notification)

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
  rescue StandardError => e
    Rails.logger.warn("[PushNotificationService] Expo deliver failed: #{e.message}")
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

  def fetch_oauth_access_token(creds)
    cache_key = "fcm_v1_access_token_#{creds['project_id']}"
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

  def flat_string_data(payload)
    out = {}
    (payload || {}).each do |k, v|
      out[k.to_s] = v.is_a?(Hash) || v.is_a?(Array) ? v.to_json : v.to_s
    end
    out
  end
end
