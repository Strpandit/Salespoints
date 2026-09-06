module Api
  class CatFiltersController < ApplicationController
    skip_before_action :authenticate_request!, only: [:index, :active_filters, :show]
    before_action :require_admin, except: [:index, :active_filters, :show]
    before_action :check_permission, except: [:index, :active_filters, :show]
    before_action :set_filter, only: [:show, :update, :destroy]

    def index
      filters = CatFilter.all
      filters = filters.where(category_id: params[:category_id]) if params[:category_id].present?
      filters = filters.order(display_order: :asc, created_at: :desc).page(params[:page]).per(params[:per_page] || 20)
      if filters.exists?
        render json: serialize_resource(filters, CatFilterSerializer).merge(
          meta: {
            current_page: filters.current_page,
            next_page: filters.next_page,
            prev_page: filters.prev_page,
            total_pages: filters.total_pages,
            total_count: filters.total_count
          },
          message: "Filters fetched successfully"
        ), status: :ok
      else
        render json: { error: "No filters found" }, status: :not_found
      end
    end

    def active_filters
      filters = CatFilter.where(is_filterable: true)
      filters = filters.where(category_id: params[:category_id]) if params[:category_id].present?
      filters = filters.order(display_order: :asc, created_at: :desc).page(params[:page]).per(params[:per_page] || 20)
      if filters.exists?
        render json: serialize_resource(filters, CatFilterSerializer).merge(
          meta: {
            current_page: filters.current_page,
            next_page: filters.next_page,
            prev_page: filters.prev_page,
            total_pages: filters.total_pages,
            total_count: filters.total_count
          },
          message: "Active Filters fetched successfully"
        ), status: :ok
      else
        render json: { error: "No active filters found" }, status: :not_found
      end
    end

    def show
      if @filter.present?
        render json: serialize_resource(@filter, CatFilterSerializer).merge(message: "Filter details fetched successfully"), status: :ok
      else
        render json: { error: "Filter not found" }, status: :not_found
      end
    end

    def create
      filter = CatFilter.new(filter_params)
      if filter.save
        render json: serialize_resource(filter, CatFilterSerializer).merge(message: "Filter created successfully"), status: :created
      else
        render json: { error: filter.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def update
      if @filter.update(filter_params)
        render json: serialize_resource(@filter, CatFilterSerializer).merge(message: "Filter updated successfully"), status: :ok
      else
        render json: { error: @filter.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def destroy
      @filter.destroy
      render json: { message: "Filter deleted successfully" }
    end

    private

    def filter_params
      permitted = params.require(:cat_filter).permit(
        :name, :data_type, :is_filterable, :category_id,
        :is_mandatory, :unit, :display_order, options: []
      )
      if params[:cat_filter][:options].is_a?(String)
        permitted[:options] = params[:cat_filter][:options].split(",").map(&:strip).reject(&:blank?)
      end
      permitted
    end

    def set_filter
      @filter = CatFilter.find_by(id: params[:id])
      render json: { error: "Filter not found" }, status: :not_found unless @filter
    end

    def check_permission
      unless current_admin.can_access?(:cat_filters) && current_admin.can_access?(:categories)
        render json: { error: "You do not have permission to manage filters. Both 'filters' and 'categories' permissions are required." }, status: :forbidden
      end
    end

    def require_admin
      render json: { error: "Admin only" }, status: :unauthorized unless current_user_type == "AdminUser"
    end

    def current_admin
      current_user
    end
  end
end
