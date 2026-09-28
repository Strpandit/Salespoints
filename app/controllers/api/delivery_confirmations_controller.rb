module Api
  class DeliveryConfirmationsController < ApplicationController
    skip_before_action :authenticate_request!
    before_action :set_confirmation

    OTP_SCOPE = "delivery_otp".freeze
    RESEND_COOLDOWN = 60.seconds

    def show
      render json: serialize_resource(@confirmation, DeliveryConfirmationSerializer, include: []).merge(
        deliverable: serialized_deliverable,
        message: "Delivery confirmation fetched successfully"
      ), status: :ok
    end

    def submit
      service.submit_form!(
        confirmation: @confirmation,
        declarations: params[:declarations] || {},
        notes: params[:notes],
        serial_numbers: params[:serial_numbers],
        files: {
          product_with_customer_image: params[:product_with_customer_image],
          product_packaging_image: params[:product_packaging_image],
          product_open_box_images: params[:product_open_box_images]
        }
      )

      render json: serialize_resource(@confirmation.reload, DeliveryConfirmationSerializer).merge(
        deliverable: serialized_deliverable,
        message: "Delivery proof submitted. OTP sent to buyer."
      ), status: :ok
    rescue StandardError => e
      render_error(e)
    end

    def resend_otps
      if @confirmation.buyer_otp_sent_at&.after?(RESEND_COOLDOWN.ago)
        return render json: { error: "Please wait a minute before requesting another OTP" }, status: :too_many_requests
      end

      service.send_otps!(@confirmation)
      clear_otp_verify_attempts!(OTP_SCOPE, @confirmation.id)

      render json: serialize_resource(@confirmation.reload, DeliveryConfirmationSerializer).merge(
        message: "OTPs sent successfully"
      ), status: :ok
    rescue StandardError => e
      render_error(e)
    end

    def verify_otps
      if otp_verify_locked?(OTP_SCOPE, @confirmation.id)
        return render json: { error: "Too many wrong attempts. Please resend the OTP to the buyer." }, status: :too_many_requests
      end

      otp_value = params[:buyer_otp].presence || params.dig(:delivery_confirmation, :buyer_otp)
      unless @confirmation.completed? || @confirmation.buyer_otp_valid?(otp_value)
        record_failed_otp_attempt!(OTP_SCOPE, @confirmation.id)
        # Once the budget is spent the OTP is burned, so it cannot be brute-forced by whoever holds the link.
        @confirmation.update_columns(buyer_otp: nil) if otp_verify_locked?(OTP_SCOPE, @confirmation.id)
      end

      confirmation = service.verify_otps!(
        confirmation: @confirmation,
        buyer_otp: otp_value
      )
      clear_otp_verify_attempts!(OTP_SCOPE, @confirmation.id)

      render json: serialize_resource(confirmation, DeliveryConfirmationSerializer).merge(
        deliverable: serialized_deliverable,
        message: "Delivery verified successfully"
      ), status: :ok
    rescue StandardError => e
      render_error(e)
    end

    private

    def set_confirmation
      @confirmation = DeliveryConfirmation.includes(:seller_dealer, :buyer, :deliverable).find_by(token: params[:token] || params[:id])
      return if @confirmation.present?

      render json: { error: "Delivery confirmation not found" }, status: :not_found
    end

    def service
      @service ||= DeliveryConfirmationService.new(deliverable: @confirmation.deliverable)
    end

    def serialized_deliverable
      case @confirmation.deliverable
      when Order
        OrderSerializer.render(@confirmation.deliverable, include: [:delivery_confirmation])
      when B2bOrder
        B2bOrderSerializer.render(@confirmation.deliverable, include: [:delivery_confirmation])
      end
    end
  end
end
