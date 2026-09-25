module Api
  module Admin
    class HeroSlidesController < ApplicationController
      include HomeBannerAdmin

      before_action :set_slide, only: [ :show, :update, :destroy, :toggle ]

      def index
        slides = HeroSlide.ordered.with_attached_image
        render json: {
          data: slides.map { |s| banner_payload.hero_slide(s, admin: true) },
          themes: HeroSlide::THEMES
        }, status: :ok
      end

      def show
        render json: { data: banner_payload.hero_slide(@slide, admin: true) }, status: :ok
      end

      def create
        slide = HeroSlide.new(slide_params)
        slide.position = (HeroSlide.maximum(:position) || -1) + 1 if params.dig(:hero_slide, :position).blank?

        if slide.save
          render json: { data: banner_payload.hero_slide(slide, admin: true), message: "Slide created" }, status: :created
        else
          render json: { error: slide.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        if @slide.update(slide_params)
          render json: { data: banner_payload.hero_slide(@slide, admin: true), message: "Slide updated" }, status: :ok
        else
          render json: { error: @slide.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # PATCH /api/admin/hero_slides/:id/toggle — show/hide on the storefront
      def toggle
        @slide.update!(is_active: !@slide.is_active)
        render json: {
          data: banner_payload.hero_slide(@slide, admin: true),
          message: @slide.is_active ? "Slide is now visible" : "Slide hidden"
        }, status: :ok
      end

      # PATCH /api/admin/hero_slides/reorder  { ids: [3, 1, 2] }
      def reorder
        ids = Array(params[:ids]).map(&:to_i)
        HeroSlide.transaction do
          ids.each_with_index { |id, index| HeroSlide.where(id: id).update_all(position: index, updated_at: Time.current) }
        end
        slides = HeroSlide.ordered.with_attached_image
        render json: { data: slides.map { |s| banner_payload.hero_slide(s, admin: true) }, message: "Order saved" }, status: :ok
      end

      def destroy
        @slide.destroy
        render json: { message: "Slide deleted" }, status: :ok
      end

      private

      def slide_params
        permitted = params.require(:hero_slide).permit(
          :badge, :title, :highlight, :subtitle, :discount_text, :cta_label, :link_url,
          :secondary_cta_label, :secondary_link_url, :theme, :position, :is_active,
          :starts_at, :ends_at, :image
        )
        permitted.delete(:image) if permitted[:image].blank?
        blank_to_nil!(permitted, :starts_at, :ends_at)
      end

      def set_slide
        @slide = HeroSlide.find_by(id: params[:id])
        render json: { error: "Slide not found" }, status: :not_found unless @slide
      end
    end
  end
end
