require "json"
require "net/http"
require "uri"

class GoogleTokenVerifier
  TOKEN_INFO_URL = "https://oauth2.googleapis.com/tokeninfo".freeze
  VALID_ISSUERS = %w[accounts.google.com https://accounts.google.com].freeze

  class << self
    # Web uses GOOGLE_CLIENT_ID. The mobile app signs in with its own Android/iOS OAuth
    # clients (same Google Cloud project), listed comma-separated in GOOGLE_MOBILE_CLIENT_IDS.
    def allowed_client_ids
      ([ENV["GOOGLE_CLIENT_ID"]] + ENV["GOOGLE_MOBILE_CLIENT_IDS"].to_s.split(","))
        .map { |id| id.to_s.strip }.reject(&:empty?).uniq
    end

    def verify(id_token)
      client_ids = allowed_client_ids
      token = id_token.to_s.strip

      return nil if client_ids.empty?
      return nil if token.empty?

      payload = fetch_token_info(token)
      return nil unless payload
      # Native Android tokens carry the app's client in `azp` and may target the web client in `aud`.
      return nil unless client_ids.include?(payload["aud"].to_s) || client_ids.include?(payload["azp"].to_s)
      return nil unless VALID_ISSUERS.include?(payload["iss"].to_s)
      return nil unless ActiveModel::Type::Boolean.new.cast(payload["email_verified"])

      {
        uid: payload["sub"],
        email: payload["email"].to_s.downcase,
        first_name: payload["given_name"],
        last_name: payload["family_name"],
        name: payload["name"]
      }
    rescue StandardError => e
      nil
    end

    private

    def fetch_token_info(id_token)
      uri = URI("#{TOKEN_INFO_URL}?id_token=#{URI.encode_www_form_component(id_token)}")
      response = Net::HTTP.get_response(uri)
      return nil unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    rescue JSON::ParserError => e
      nil
    end
  end
end
