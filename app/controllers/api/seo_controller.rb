module Api
  # Public, unauthenticated SEO endpoints (read-only).
  class SeoController < ApplicationController
    skip_before_action :authenticate_request!
    skip_after_action :apply_noindex_header

    SITEMAP_CACHE_KEY = "seo/sitemap/v1".freeze
    SITEMAP_TTL = 1.hour

    # GET /api/seo/sitemap.xml  (also served at /sitemap.xml)
    # Fresh view of every public URL: static pages, categories, products (with images) and live Offer Mart deals.
    def sitemap
      xml = Rails.cache.fetch(SITEMAP_CACHE_KEY, expires_in: SITEMAP_TTL) do
        Seo::SitemapBuilder.new(base_url: request.base_url).call
      end

      response.set_header("Cache-Control", "public, max-age=#{SITEMAP_TTL.to_i}")
      render plain: xml, content_type: "application/xml"
    end
  end
end
