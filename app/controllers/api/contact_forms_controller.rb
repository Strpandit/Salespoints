module Api
  # Public "Contact Us" form (web + mobile) and the admin inbox for it.
  class ContactFormsController < ApplicationController
    skip_before_action :authenticate_request!, only: :create
    before_action :require_admin!, except: :create
    before_action :set_submission, only: %i[show respond]

    # Public endpoint: keep bots from flooding the inbox and the admins' email.
    rate_limit to: 5, within: 10.minutes, only: :create, name: "contact-form", by: -> { client_ip },
               with: -> { render json: { success: false, error: "Too many messages. Please try again later." }, status: :too_many_requests }

    def create
      submission = ContactFormSubmission.new(contact_form_params.merge(status: "received"))

      if submission.save
        notify_admins(submission)
        render json: {
          success: true,
          message: "Thank you for contacting us. We will get back to you soon.",
          data: { id: submission.id }
        }, status: :created
      else
        render json: {
          success: false,
          error: submission.errors.full_messages.to_sentence,
          errors: submission.errors
        }, status: :unprocessable_entity
      end
    end

    def index
      scope = ContactFormSubmission.includes(:admin_user).recent
      scope = scope.where(status: params[:status]) if ContactFormSubmission::STATUSES.include?(params[:status].to_s)

      if params[:search].present?
        q = "%#{ActiveRecord::Base.sanitize_sql_like(params[:search].to_s.strip)}%"
        scope = scope.where("name ILIKE :q OR email ILIKE :q OR phone ILIKE :q OR subject ILIKE :q", q: q)
      end

      status_counts = ContactFormSubmission.group(:status).count
      page = scope.page(params[:page]).per(params[:per_page].presence || 20)

      render json: {
        success: true,
        data: page.map { |submission| serialize(submission) },
        meta: {
          current_page: page.current_page,
          next_page: page.next_page,
          prev_page: page.prev_page,
          total_pages: page.total_pages,
          total_count: page.total_count,
          status_counts: status_counts
        }
      }
    end

    def show
      # update_columns: marking as read must not fail on older rows that predate the length validations.
      @submission.update_columns(status: "read", updated_at: Time.current) if @submission.received?
      render json: { success: true, data: serialize(@submission) }
    end

    def respond
      response_text = params[:response].to_s.strip
      if response_text.length < 2
        return render json: { success: false, error: "Please write a response" }, status: :unprocessable_entity
      end
      if response_text.length > 5000
        return render json: { success: false, error: "Response is too long (max 5000 characters)" }, status: :unprocessable_entity
      end

      @submission.update_columns(
        admin_response: response_text,
        admin_user_id: current_admin.id,
        status: "responded",
        responded_at: Time.current,
        updated_at: Time.current
      )
      ContactMailer.contact_form_response(@submission).deliver_later

      render json: { success: true, message: "Response sent successfully", data: serialize(@submission.reload) }
    end

    private

    def require_admin!
      render json: { success: false, error: "Admin access required" }, status: :forbidden unless current_admin
    end

    def set_submission
      @submission = ContactFormSubmission.find_by(id: params[:id])
      render json: { success: false, error: "Message not found" }, status: :not_found unless @submission
    end

    def contact_form_params
      params.require(:contact_form).permit(:name, :email, :phone, :subject, :message)
    end

    def serialize(submission)
      {
        id: submission.id,
        name: submission.name,
        email: submission.email,
        phone: submission.phone,
        subject: submission.subject,
        message: submission.message,
        status: submission.status,
        admin_response: submission.admin_response,
        responded_at: submission.responded_at,
        responded_by: submission.admin_user && { id: submission.admin_user.id, name: submission.admin_user.full_name },
        created_at: submission.created_at
      }
    end

    # Alerts are best effort: a mail or notification hiccup must never fail the customer's submission.
    def notify_admins(submission)
      AdminUser.where(is_super_admin: true, status: "active").find_each do |admin|
        Notification.create!(
          receiver: admin,
          notifiable: submission,
          notification_type: "contact_form",
          title: "New Contact Form Submission",
          body: "New message from #{submission.name}: #{submission.subject}",
          payload: { contact_form_submission_id: submission.id, path: "/admin/contact-messages" }
        )
        ContactMailer.new_contact_form(submission, admin).deliver_later
      rescue StandardError => e
        Rails.logger.error("[contact_forms] admin notification failed for admin #{admin.id}: #{e.class}: #{e.message}")
      end
    end
  end
end
