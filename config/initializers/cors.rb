# Be sure to restart your server when you modify this file.

# Browsers may only call the API from these origins. Native mobile apps are not subject to CORS.
PRODUCTION_ORIGINS = [
  "https://salespoints.netlify.app",
  "https://salespoints.in",
  "https://www.salespoints.in"
].freeze

# Local web (Vite) and Expo web dev servers; never allowed in production.
DEVELOPMENT_ORIGINS = [
  %r{\Ahttp://(localhost|127\.0\.0\.1)(:\d+)?\z}
].freeze

# Extra origins (e.g. a staging site) can be added without a code change: CORS_EXTRA_ORIGINS=https://a.com,https://b.com
EXTRA_ORIGINS = ENV.fetch("CORS_EXTRA_ORIGINS", "").split(",").map(&:strip).reject(&:empty?).freeze

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins(*PRODUCTION_ORIGINS, *EXTRA_ORIGINS, *(Rails.env.production? ? [] : DEVELOPMENT_ORIGINS))

    resource "*",
      headers: :any,
      expose: ['Authorization', 'Content-Disposition'],
      methods: [:get, :post, :put, :patch, :delete, :options, :head],
      credentials: true
  end
end
