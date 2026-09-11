class OfferMartBuyNowService
  include Rails.application.routes.url_helpers

  Result = Struct.new(:order, :payment_data, keyword_init: true)

  RESERVATION_WINDOW = 4.hours

  def initialize(buyer:, dealer_offer:, quantity:, payment_method:, shipping_address:, billing_address: nil, pincode:)
    @buyer = buyer
    @offer = dealer_offer
    @quantity = quantity.to_i.positive? ? quantity.to_i : 1
    @payment_method = payment_method.to_s.presence || "cod"
    @shipping_address = (shipping_address || {}).to_h.stringify_keys
    @billing_address = (billing_address.presence || @shipping_address).to_h.stringify_keys
    @pincode = pincode.to_s.strip
  end

  def call
    raise StandardError, "Invalid payment method" unless Order::PAYMENT_METHODS.include?(@payment_method)
    raise StandardError, "Pincode is required for delivery" if @pincode.blank?

    offer = DealerOffer.includes(:dealer, :product_variant).find_by(id: @offer.id)
    raise StandardError, "Offer not found" unless offer
    raise StandardError, "This offer is no longer available" unless offer.live?
    raise StandardError, "Seller is currently unavailable" unless offer.dealer&.status == "active"
    raise StandardError, "This offer is not available for your pincode" unless offer.pincodes.include?(@pincode)
    raise StandardError, "Only #{offer.remaining_quantity} unit(s) left for this offer" if offer.remaining_quantity < @quantity

    pricing = calculate_pricing(offer)

    order = nil
    payment_data = {}
    cod = @payment_method == "cod"

    ActiveRecord::Base.transaction do
      order = Order.create!(
        buyer: @buyer,
        seller_dealer_id: offer.dealer_id,
        dealer_offer_id: offer.id,
        status: cod ? "processing" : "pending",
        accepted_at: cod ? Time.current : nil,
        processing_at: cod ? Time.current : nil,
        subtotal_amount: pricing[:subtotal],
        tax_amount: pricing[:gst_amount],
        discount_amount: 0,
        total_amount: pricing[:total],
        coupon_code: nil,
        payment_method: @payment_method,
        payment_status: "pending",
        payment_gateway: cod ? nil : "cashfree",
        billing_address: @billing_address,
        shipping_address: @shipping_address,
        commission_rate: 0,
        commission_amount: 0,
        marketplace_fee_amount: 0,
        seller_settlement_amount: 0,
        settlement_status: "pending",
        refund_status: "none",
        refund_amount: 0,
        placed_at: Time.current,
        status_note: "Offer Mart order — #{offer.offer_name}"
      )

      OrderItem.create!(
        order: order,
        product_variant_id: offer.product_variant_id,
        dealer_product_id: offer.dealer_product_id,
        quantity: @quantity,
        unit_price: pricing[:unit_price],
        total_price: pricing[:subtotal]
      )

      # Reserve stock immediately for both COD and online so limited-stock offers cannot oversell.
      offer.deduct_quantity!(@quantity)
    end

    if cod
      notify_offer_order_placed(order, offer)
      safe_dispatch_placed_email(order)
    else
      payment_data = create_online_payment(order)
      ExpireOfferMartOrderJob.set(wait: RESERVATION_WINDOW).perform_later(order.id)
    end

    Result.new(order: order, payment_data: payment_data)
  end

  private

  def calculate_pricing(offer)
    unit_price = offer.offer_price.to_d
    subtotal = (unit_price * @quantity).round(2)
    rate = offer.effective_tax_rate
    gst_amount = rate.zero? ? 0.to_d : (subtotal - (subtotal / (1 + rate / 100))).round(2)

    {
      unit_price: unit_price,
      subtotal: subtotal,
      gst_amount: gst_amount,
      total: subtotal
    }
  end

  def notify_offer_order_placed(order, offer)
    NotificationService.deliver(
      recipient: offer.dealer,
      actor: @buyer,
      notifiable: order,
      kind: "offer_mart_order_placed",
      title: "\u{1F3F7}\uFE0F New Offer Mart Order",
      message: "#{@buyer.full_name} bought #{@quantity} unit(s) of #{offer.offer_name}. Total: \u20b9#{order.total_amount}",
      visible_in_app: true,
      delivery_channels: { push: true, whatsapp: true, sms: false, email: true, in_app: true },
      payload: {
        order_id: order.order_number,
        dealer_offer_id: offer.id,
        offer_name: offer.offer_name,
        quantity: @quantity,
        total_amount: order.total_amount.to_f
      }
    )

    NotificationService.deliver(
      recipient: @buyer,
      actor: @buyer,
      notifiable: order,
      kind: "offer_mart_order_confirmation",
      title: "\u2705 Order Placed",
      message: "Your order ##{order.order_number} for #{offer.offer_name} has been placed with the seller.",
      visible_in_app: true,
      delivery_channels: { push: true, whatsapp: true, sms: false, email: true, in_app: true },
      payload: {
        order_id: order.order_number,
        status: order.status,
        total_amount: order.total_amount.to_f
      }
    )

    # WhatsApp notifications (async via background job)
    safe_send_whatsapp_notifications(order, offer)
  end

  def safe_dispatch_placed_email(order)
    EmailDispatcherService.retail_order_placed(order)
  rescue StandardError => e
    Rails.logger.warn("[OfferMartBuyNowService] placed email skipped: #{e.message}")
  end

  def safe_send_whatsapp_notifications(order, offer)
    delivery_addr = [ @shipping_address["address_line1"], @shipping_address["city"],
                      @shipping_address["state"], @pincode ].compact.join(", ")

    # Customer WhatsApp
    customer_phone = @buyer.try(:phone).to_s.strip
    if customer_phone.present?
      MetaWhatsappCloudService.deliver_later(
        :send_offer_mart_order_customer,
        to: customer_phone,
        buyer_name: @buyer.try(:full_name) || "Customer",
        order_number: order.order_number,
        offer_name: offer.offer_name,
        quantity: @quantity,
        total: order.total_amount.to_f,
        delivery_pincode: @pincode,
        payment_method: @payment_method
      )
    end

    # Dealer WhatsApp
    dealer_phone = offer.dealer.try(:phone).to_s.strip
    if dealer_phone.present?
      MetaWhatsappCloudService.deliver_later(
        :send_offer_mart_order_dealer,
        to: dealer_phone,
        order_number: order.order_number,
        buyer_name: @buyer.try(:full_name) || "Customer",
        offer_name: offer.offer_name,
        quantity: @quantity,
        total: order.total_amount.to_f,
        delivery_address: delivery_addr,
        payment_method: @payment_method
      )
    end
  rescue StandardError => e
    Rails.logger.warn("[OfferMartBuyNowService] WhatsApp skipped: #{e.message}")
  end

  # Mirrors DirectBuyNowService#create_online_payment
  def create_online_payment(order)
    attempt = PaymentAttempt.create!(
      buyer: @buyer,
      status: "pending",
      amount: order.total_amount,
      currency: "INR",
      payment_gateway: "cashfree",
      result_payload: {
        checkout_context: "offer_mart_order",
        order_ids: [ order.id ],
        request_metadata: {
          order_id: order.id,
          dealer_offer_id: order.dealer_offer_id,
          quantity: @quantity,
          pincode: @pincode
        }
      }
    )

    cashfree = CashfreeService.new
    payload = cashfree.create_cashfree_order(
      reference: attempt.attempt_number,
      amount: attempt.amount,
      customer: @buyer,
      return_params: {
        payment_attempt_id: attempt.id,
        order_id: order.id
      }
    )

    attempt.update!(
      gateway_order_reference: payload["cf_order_id"] || payload["order_id"] || attempt.attempt_number,
      payment_session_id: payload["payment_session_id"],
      payment_gateway_payload: payload
    )

    order.update!(
      gateway_order_reference: attempt.gateway_order_reference,
      payment_gateway_payload: payload
    )

    {
      payment_session_id: attempt.payment_session_id,
      gateway_order_reference: attempt.gateway_order_reference,
      payment_attempt_id: attempt.id,
      provider: "cashfree"
    }
  rescue StandardError => e
    order.update_columns(payment_status: "failed", status_note: "Payment initialization failed")
    raise e
  end
end
