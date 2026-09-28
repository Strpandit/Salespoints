module Api
  class ReviewsController < ApplicationController
    skip_before_action :authenticate_request!, only: [:index]
    before_action :set_reviewable, only: [:index, :create]

    def index
      if @reviewable.present?
        reviews = @reviewable.reviews.order(created_at: :desc)
        paginated = reviews.page(params[:page]).per(params[:per_page] || 20)

        render json: serialize_resource(paginated, ReviewSerializer).merge(
          meta: {
            current_page: paginated.current_page,
            next_page: paginated.next_page,
            prev_page: paginated.prev_page,
            total_pages: paginated.total_pages,
            total_count: paginated.total_count
          },
          message: "Reviews fetched successfully"
        ), status: :ok
      else
        render json: { error: "Reviewable not found" }, status: :not_found
      end
    end

    def create
      # Reviews belong to customer accounts (reviews.account_id is required).
      return render json: { error: "Only customer accounts can write product reviews" }, status: :forbidden unless current_account

      # ✅ Check if user already reviewed
      if existing_review?
        return render json: { 
          error: "You have already reviewed this product" 
        }, status: :unprocessable_entity
      end

      unless user_verified?(@reviewable)
        return render json: {
          error: "Only customers who have received this product can review it"
        }, status: :forbidden
      end

      review = @reviewable.reviews.new(review_params)
      review.account = current_account
      review.verified = true

      if review.save
        render json: serialize_resource(review, ReviewSerializer).merge(
          message: "Review submitted successfully"
        ), status: :created
      else
        render json: { error: review.errors.full_messages }, status: :unprocessable_entity
      end
    end

    private

    def set_reviewable
      if params[:product_id].present?
        @reviewable = Product.find_by(id: params[:product_id])
        if @reviewable.blank?
          render json: { error: "Product not found" }, status: :not_found and return
        end
        return
      end

      if params[:dealer_product_id].present?
        @reviewable = DealerProduct.find_by(id: params[:dealer_product_id])
        if @reviewable.blank?
          render json: { error: "Dealer product not found" }, status: :not_found and return
        end
        return
      end

      render json: { error: "Product ID or Dealer Product ID required" }, status: :bad_request
    end

    def review_params
      params.require(:review).permit(:title, :comment, :rating)
    end

    def existing_review?
      if @reviewable.is_a?(Product)
        Review.exists?(account_id: current_account.id, product_id: @reviewable.id)
      elsif @reviewable.is_a?(DealerProduct)
        Review.exists?(account_id: current_account.id, dealer_product_id: @reviewable.id)
      else
        false
      end
    end

    # Every status an order can reach after it was handed to the customer.
    RECEIVED_ORDER_STATUSES = %w[
      delivered return_requested return_approved return_in_transit returned
      replacement_requested replacement_approved replacement_shipped replacement_delivered
    ].freeze

    def user_verified?(reviewable)
      return false unless current_account

      received_items = OrderItem.joins(:order).where(
        orders: { buyer_type: "Account", buyer_id: current_account.id, status: RECEIVED_ORDER_STATUSES }
      )

      case reviewable
      when Product
        received_items.joins(:product_variant).where(product_variants: { product_id: reviewable.id }).exists?
      when DealerProduct
        received_items.where(dealer_product_id: reviewable.id).exists?
      else
        false
      end
    end
  end
end