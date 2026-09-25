module Api
  # Public, unauthenticated home-page content managed from the admin panel.
  class StorefrontController < ApplicationController
    skip_before_action :authenticate_request!

    # GET /api/storefront/hero_slides  → { data: [] } when no slide is live
    def hero_slides
      slides = HeroSlide.visible.ordered.with_attached_image.select { |s| s.image.attached? }
      render json: { data: slides.map { |s| payload.hero_slide(s) } }, status: :ok
    end

    # GET /api/storefront/flash_sale  → { data: null } when nothing is running
    def flash_sale
      sale = FlashSale.current
      render json: { data: sale && payload.flash_sale(sale) }, status: :ok
    end

    private

    def payload
      @payload ||= Storefront::BannerPayload.new(base_url: request.base_url)
    end
  end
end
