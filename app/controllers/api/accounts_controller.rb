module Api
  class AccountsController < ApplicationController
    before_action :authenticate_request!
    before_action :require_admin, only: [:index, :block, :unblock]
    before_action :check_permission, only: [:index, :block, :unblock]
    before_action :set_account, only: [:show, :update, :destroy, :block, :unblock]
    before_action :authorize_account!, only: [:show, :update]

    def index
      @accounts = Account.all

      if params[:status].present? && params[:status] != "all"
        @accounts = @accounts.where(status: params[:status])
      end

      if params[:email_verified].present? && params[:email_verified] != "all"
        is_ver = ActiveModel::Type::Boolean.new.cast(params[:email_verified])
        if is_ver
          @accounts = @accounts.where("status = 'active' OR google_signup = true")
        else
          @accounts = @accounts.where("status = 'pending' AND google_signup = false")
        end
      end

      if params[:date_from].present?
        from = Date.parse(params[:date_from]).beginning_of_day rescue nil
        @accounts = @accounts.where("created_at >= ?", from) if from
      end

      if params[:date_to].present?
        to = Date.parse(params[:date_to]).end_of_day rescue nil
        @accounts = @accounts.where("created_at <= ?", to) if to
      end

      if params[:search].present?
        search = "%#{params[:search].strip.downcase}%"

        @accounts = @accounts.where(
          "LOWER(first_name) LIKE :search
          OR LOWER(last_name) LIKE :search
          OR LOWER(email) LIKE :search
          OR phone LIKE :search",
          search: search
        )
      end

      case params[:sort_by]
      when "oldest"
        @accounts = @accounts.reorder(created_at: :asc)
      when "name_asc"
        @accounts = @accounts.reorder(first_name: :asc)
      when "name_desc"
        @accounts = @accounts.reorder(first_name: :desc)
      else
        @accounts = @accounts.reorder(created_at: :desc)
      end

      @accounts = @accounts.page(params[:page]).per(params[:per_page] || 20)
      render json: serialize_resource(@accounts, AccountSerializer).merge(
        meta: {
          current_page: @accounts.current_page,
          next_page: @accounts.next_page,
          prev_page: @accounts.prev_page,
          total_pages: @accounts.total_pages,
          total_count: @accounts.total_count,
          statuses: ["all"] + Account.statuses.keys
        },
        message: 'Account list fetched successfully'
      ), status: :ok
    end

    def show
      render json: serialize_resource(@account, AccountSerializer).merge(
        message: 'User Details'
      ), status: :ok
    end

    def update
      if @account.update(account_params)
        render json: { account: serialize_data(@account, AccountSerializer), message: "Account updated successfully" }, status: :ok
      else
        render json: { errors: @account.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def destroy
      render json: {
        message: "Account deletion requires admin approval. Submit a request from Security settings in your profile."
      }, status: :forbidden
    end

    def block
      @account.update!(status: 'banned')
      @account.revoke_tokens!
      
      # Send account blocked email
      AccountMailer.account_blocked(@account).deliver_later if @account.email.present?
      
      render json: { message: "Account blocked successfully" }, status: :ok
    end

    def unblock
      @account.update!(status: 'active')
      
      # Send account unblocked email
      AccountMailer.account_unblocked(@account).deliver_later if @account.email.present?
      
      render json: { message: "Account unblocked successfully" }, status: :ok
    end

    def change_password
      unless current_account.authenticate(params[:current_password])
        return unauthorized("Incorrect current password")
      end

      if current_account.update(
        password: params[:new_password],
        password_confirmation: params[:confirm_password]
      )
        render json: { status: 200, message: "Password changed successfully" }, status: :ok
      else
        render json: { error: current_account.errors.full_messages }, status: :unprocessable_entity
      end
    end

    private

    def set_account
      @account = Account.find(params[:id])
    end

    def authorize_account!
      unless current_account && current_account.id == @account.id
        render json: { error: 'Not authorized' }, status: :forbidden
      end
    end

    # Customers edit their own profile here. `status` (active/banned…) and `google_signup` are
    # server-controlled — status only changes via OTP activation or admin block/unblock —
    # so they are never accepted from this endpoint.
    def account_params
      params.require(:account).permit(:first_name, :last_name, :email, :phone, :country_code, :gender, :password, :password_confirmation)
    end

    def check_permission
      required_permission = %w[block unblock].include?(action_name) ? :write : :read

      unless current_admin.can_access?(:accounts, required_permission)
        render json: { error: "You do not have permission to manage customers"}, status: :forbidden
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
