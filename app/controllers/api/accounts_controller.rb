module Api
  class AccountsController < ApplicationController
    include PasswordPolicy

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
      attrs = account_params
      password_error = guard_password_change(attrs)
      return render json: { errors: [password_error], error: password_error }, status: :unprocessable_entity if password_error

      password_changed = attrs[:password].present?
      if @account.update(attrs)
        @account.revoke_tokens! if password_changed && @password_was_set
        render json: { account: serialize_data(@account, AccountSerializer), message: "Account updated successfully" }, status: :ok
      else
        render json: { errors: @account.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def destroy
      unless current_user_type == "AdminUser"
        return render json: {
          message: "Account deletion requires admin approval. Submit a request from Security settings in your profile.",
          error: "Account deletion requires admin approval. Submit a request from Security settings in your profile."
        }, status: :forbidden
      end

      unless current_admin.super_admin?
        return render json: { error: "Only super admin can delete customer accounts" }, status: :forbidden
      end

      account_name = @account.try(:full_name).presence || @account.email.presence || "Account ##{@account.id}"

      @account.revoke_tokens!
      if @account.destroy
        ActivityLogger.log(actor: current_admin, action: "customer_deleted", category: "admin_action",
                           description: "Deleted customer account #{account_name}", request: request)
        render json: { message: "Customer account deleted successfully" }, status: :ok
      else
        render json: { error: @account.errors.full_messages.presence || ["Customer account could not be deleted"] }, status: :unprocessable_entity
      end
    end

    def block
      @account.update!(status: 'banned')
      @account.revoke_tokens!
      
      # Send account blocked email
      AccountMailer.account_blocked(@account).deliver_later if @account.email.present?
      
      render json: { message: "Account blocked successfully" }, status: :ok
    end

    def unblock
      unless %w[banned inactive].include?(@account.status)
        return render json: { error: "Only a blocked or inactive account can be unblocked (current status: #{@account.status})" }, status: :unprocessable_entity
      end

      @account.update!(status: 'active')
      
      # Send account unblocked email
      AccountMailer.account_unblocked(@account).deliver_later if @account.email.present?
      
      render json: { message: "Account unblocked successfully" }, status: :ok
    end

    def change_password
      return unauthorized("Customer account required") unless current_account

      unless current_account.authenticate(params[:current_password])
        return unauthorized("Incorrect current password")
      end

      policy_error = password_policy_error(params[:new_password], params[:confirm_password])
      return render_password_policy_error(policy_error) if policy_error

      if current_account.update(
        password: params[:new_password],
        password_confirmation: params[:new_password].to_s
      )
        current_account.revoke_tokens!
        render json: { status: 200, message: "Password changed successfully", token: JsonWebToken.issue_for(current_account) }, status: :ok
      else
        render json: { error: current_account.errors.full_messages }, status: :unprocessable_entity
      end
    end

    private

    def guard_password_change(attrs)
      @password_was_set = false
      return nil unless attrs[:password].present?

      if @account.password_digest.present?
        @password_was_set = true
        if ENV.fetch("ACCOUNT_UPDATE_REQUIRE_CURRENT_PASSWORD", "true") != "false"
          current = params[:current_password].presence || params[:old_password].presence ||
                    params.dig(:account, :current_password).presence || params.dig(:account, :old_password).presence
          return "Current password is required to change your password" if current.blank?
          return "Incorrect current password" unless @account.authenticate(current.to_s)
        end
      end

      password_policy_error(attrs[:password], attrs[:password_confirmation])
    end

    def set_account
      @account = Account.find_by(id: params[:id])
      render json: { error: "Account not found" }, status: :not_found unless @account
    end

    def authorize_account!
      unless current_account && current_account.id == @account.id
        render json: { error: 'Not authorized' }, status: :forbidden
      end
    end

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
