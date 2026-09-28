module Api
  class DeletionRequestsController < ApplicationController
    before_action :authenticate_request!
    before_action :set_deletion_request,  only: [:approve, :reject, :cancel]

    before_action :require_super_admin!, only: [:index, :approve, :reject]

    def create
      requestable = current_requestable
      return render json: { error: "Unauthorized" }, status: :forbidden unless requestable

      return render json: {
        error: "Super admin cannot request account deletion"
      }, status: :forbidden if super_admin_request?(requestable)

      unless verify_password(requestable)
        return render json: {
          error: "Incorrect password"
        }, status: :unauthorized
      end

      if requestable.deletion_requests.pending.exists?
        return render json: {
          error: "Deletion request already pending"
        }, status: :unprocessable_entity
      end

      deletion_request =
        requestable.deletion_requests.create!(
          status: "pending",
          reason: params[:reason],
          requested_at: Time.current,
          password_verified_at: Time.current
        )

      DeletionNotificationService.request_created(deletion_request)
      DeletionMailService.request_created(deletion_request)

      render json: {
        message: "Deletion request submitted successfully"
      }, status: :created
    end

    def index
      requests = DeletionRequest
          .includes(:requestable, :reviewed_by_admin)
          .order(created_at: :desc)

      requests = requests.where(requestable_type: params[:type]) if params[:type].present?
      requests = requests.where(status: params[:status]) if params[:status].present?

      requests = requests
        .page(params[:page])
        .per(params[:per_page] || 20)

      render json: {
        data: requests.map { |request| serialize_request(request) },
        meta: {
          current_page: requests.current_page,
          next_page: requests.next_page,
          prev_page: requests.prev_page,
          total_pages: requests.total_pages,
          total_count: requests.total_count
        }
      }
    end

    def approve
      return already_processed unless @deletion_request.pending?

      account = @deletion_request.requestable

      ActiveRecord::Base.transaction do
        # Dealers/staff record who deleted them (customer accounts have no such column). Written
        # directly so an unrelated validation on an old record can't block the deletion.
        account.update_columns(deleted_by_id: current_admin.id) if account.has_attribute?(:deleted_by_id)

        account.destroy

        @deletion_request.update!(
          status: "approved",
          reviewed_at: Time.current,
          reviewed_by_admin: current_admin
        )
      end

      DeletionNotificationService.approved(@deletion_request, current_admin)
      DeletionMailService.approved(@deletion_request, current_admin)

      render json: {
        message: "Account deleted successfully"
      }
    end

    def reject
      return already_processed unless @deletion_request.pending?

      reason =
        params[:rejection_reason].presence ||
        "Request rejected by super administrator"

      @deletion_request.update!(
        status: "rejected",
        reviewed_at: Time.current,
        reviewed_by_admin: current_admin,
        rejection_reason: reason
      )

      DeletionNotificationService.rejected(@deletion_request, current_admin, reason)
      DeletionMailService.rejected(@deletion_request, reason)

      render json: {
        message: "Request rejected successfully"
      }
    end

    # DELETE /api/deletion_requests/cancel_pending — the signed-in user withdraws their own
    # pending request (apps don't need to know the request id).
    def cancel_pending
      requestable = current_requestable
      return render json: { error: "Unauthorized" }, status: :forbidden unless requestable

      request_record = requestable.deletion_requests.pending.order(created_at: :desc).first
      return render json: { error: "No pending deletion request found" }, status: :not_found unless request_record

      request_record.destroy!
      render json: { message: "Deletion request cancelled successfully" }
    end

    def cancel
      requestable = current_requestable

      unless @deletion_request.requestable == requestable
        return render json: {
          error: "Unauthorized"
        }, status: :forbidden
      end

      return already_processed unless @deletion_request.pending?

      @deletion_request.destroy!

      render json: {
        message: "Deletion request cancelled successfully"
      }
    end

    private

    def set_deletion_request
      @deletion_request = DeletionRequest.find_by(id: params[:id])

      return if @deletion_request.present?

      render json: {
        error: "Deletion request not found"
      }, status: :not_found
    end

    def require_super_admin!
      unless current_user_type == "AdminUser" &&
             current_admin.super_admin?
        render json: {
          error: "Only super admin can perform this action"
        }, status: :forbidden
      end
    end

    def current_admin
      current_user
    end

    # Customers (Account), dealers and staff can all ask for their account to be deleted.
    def current_requestable
      case current_user_type.to_s.strip
      when "AdminUser", "Dealer", "Account"
        current_user
      end
    end

    def verify_password(user)
      user.authenticate(params[:password])
    end

    def super_admin_request?(user)
      user.is_a?(AdminUser) && user.super_admin?
    end

    def already_processed
      render json: {
        error: "Request already processed"
      }, status: :unprocessable_entity
    end

    def serialize_request(request)
      # After approval the account is soft-deleted, so the default association returns nil.
      account = request.requestable || deleted_requestable(request)

      {
        id: request.id,
        type: request.requestable_type,
        status: request.status,
        reason: request.reason,
        rejection_reason: request.rejection_reason,
        requested_at: request.requested_at,
        reviewed_at: request.reviewed_at,

        account: {
          id: account&.id || request.requestable_id,
          name: account.try(:full_name).presence || account.try(:email) || "Deleted account",
          email: account.try(:email),
          phone: account.try(:phone)
        }
      }
    end

    def deleted_requestable(request)
      klass = request.requestable_type.safe_constantize
      return nil unless klass

      scope = klass.respond_to?(:with_deleted) ? klass.with_deleted : klass
      scope.find_by(id: request.requestable_id)
    end
  end
end