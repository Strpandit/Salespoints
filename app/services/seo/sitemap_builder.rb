require "cgi"

module Seo
  # Builds the public XML sitemap (static pages + categories + products with images + live Offer Mart deals).
  #
  # URLs point at the WEB storefront (SEO_SITE_URL, default https://salespoints.in) — never at the API host.
  # Read-only: it only runs SELECTs and never touches orders / payments / auth.
  class SitemapBuilder
    SITE_URL = ENV.fetch("SEO_SITE_URL", "https://salespoints.in").chomp("/").freeze

    MAX_PRODUCTS = 40_000
    MAX_OFFERS   = 1_000
    MAX_IMAGES_PER_PRODUCT = 5

    # [path, changefreq, priority]
    STATIC_PAGES = [
      ["/",                 "daily",   "1.0"],
      ["/shop",             "daily",   "0.9"],
      ["/offer-mart",       "daily",   "0.9"],
      ["/dealer/signup",    "monthly", "0.7"],
      ["/about",            "monthly", "0.6"],
      ["/contact",          "monthly", "0.6"],
      ["/faq",              "monthly", "0.6"],
      ["/shipping-policy",  "yearly",  "0.3"],
      ["/privacy-policy",   "yearly",  "0.3"],
      ["/terms-conditions", "yearly",  "0.3"]
    ].freeze

    # Real top-level routes in the React app — a category whose slug equals one of these can never be reached.
    RESERVED_SLUGS = %w[
      about contact shipping-policy privacy-policy faq terms-conditions login forgot-password set-password
      user-profile shop offer-mart checkout product payment-status payment delivery-confirmation order-waiting
      dealer admin assets
    ].freeze

    def initialize(base_url: nil)
      @base_url = base_url
    end

    def call
      xml = +%(<?xml version="1.0" encoding="UTF-8"?>\n)
      xml << %(<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:image="http://www.google.com/schemas/sitemap-image/1.1">\n)
      STATIC_PAGES.each { |path, freq, prio| xml << url_node(path, changefreq: freq, priority: prio) }
      categories.each do |cat|
        xml << url_node("/#{cat.slug}", lastmod: cat.updated_at, changefreq: "daily", priority: "0.8")
      end
      each_product { |product| xml << product_node(product) }
      live_offers.each do |offer|
        xml << url_node("/offer-mart/#{offer.to_param}", lastmod: offer.updated_at, changefreq: "daily", priority: "0.5")
      end
      xml << "</urlset>\n"
    end

    private

    def categories
      @categories ||= Category.where.not(is_active: false).where.not(slug: [nil, ""]).order(:id)
                              .reject { |c| RESERVED_SLUGS.include?(c.slug) }
    end

    def each_product(&block)
      scope = Product.active
                     .joins(:category)
                     .where.not(categories: { is_active: false })
                     .where.not(slug: [nil, ""])
                     .includes(:category, media_attachments: :blob)
                     .order(:id)
                     .limit(MAX_PRODUCTS)
      scope.find_each(batch_size: 500, &block)
    end

    def live_offers
      DealerOffer.visible_to_marketplace.where.not(slug: [nil, ""]).order(updated_at: :desc).limit(MAX_OFFERS).to_a
    rescue StandardError => e
      Rails.logger.warn("[Seo::SitemapBuilder] offers skipped: #{e.class}: #{e.message}")
      []
    end

    def product_node(product)
      category = product.category
      return "" if category.nil? || category.slug.blank? || RESERVED_SLUGS.include?(category.slug)

      url_node("/#{category.slug}/#{product.slug}",
               lastmod: product.updated_at, changefreq: "weekly", priority: "0.7",
               images: product_images(product), image_title: product.name)
    end

    def product_images(product)
      product.ordered_media_attachments
             .map(&:blob)
             .select { |blob| blob&.content_type.to_s.start_with?("image/") }
             .first(MAX_IMAGES_PER_PRODUCT)
             .filter_map { |blob| BlobUrlHelper.blob_url(blob, host: @base_url) }
    rescue StandardError => e
      Rails.logger.warn("[Seo::SitemapBuilder] images skipped for product #{product.id}: #{e.class}")
      []
    end

    def url_node(path, lastmod: nil, changefreq: nil, priority: nil, images: [], image_title: nil)
      node = +"  <url>\n    <loc>#{esc(SITE_URL + (path == '/' ? '/' : path))}</loc>\n"
      node << "    <lastmod>#{lastmod.utc.iso8601}</lastmod>\n" if lastmod
      node << "    <changefreq>#{changefreq}</changefreq>\n" if changefreq
      node << "    <priority>#{priority}</priority>\n" if priority
      images.each do |src|
        node << "    <image:image><image:loc>#{esc(src)}</image:loc>"
        node << "<image:title>#{esc(image_title.to_s.truncate(120))}</image:title>" if image_title.present?
        node << "</image:image>\n"
      end
      node << "  </url>\n"
    end

    def esc(value)
      CGI.escapeHTML(value.to_s)
    end
  end
end
