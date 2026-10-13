class OrderLifecycleService
  # Statuses in which a seller's stock has already been deducted but the goods have not reached the buyer.
  RESTOCK_ON_CANCEL_FROM = %w[processing shipped].freeze

  def initialize(order:, actor: nil, status_note: nil)
    @order = order
    @actor = actor
    @status_note = status_note
  end

  def transition!(next_status:)
    next_status = next_status.to_s

    # Row lock + re-check: two concurrent transitions (double tap, seller + admin, OTP verify twice) must not
    # both pass the validity check against a stale status (double refund, double stock restore).
    @order.with_lock do
      raise StandardError, "Invalid status transition" unless @order.can_transition_to?(next_status)

      previous_status = @order.status.to_s
      attrs = { status: next_status, status_note: @status_note.presence || @order.status_note }
      now = Time.current

      case next_status
      when "processing"
        attrs[:processing_at] = @order.processing_at || now
      when "shipped", "replacement_shipped"
        attrs[:shipped_at] = @order.shipped_at || now
      when "delivered", "replacement_delivered"
        delivered_at = @order.delivered_at || now
        attrs[:delivered_at] = delivered_at
        attrs[:return_window_closes_at] = delivered_at + MarketplaceOrderFinancials.return_window_days.days
        attrs[:settlement_due_at] = delivered_at + MarketplaceOrderFinancials.settlement_hold_days.days
        attrs[:settlement_status] = @order.seller_settlement_amount.to_d.positive? ? "pending" : "refunded"
      when "cancelled"
        attrs[:cancelled_at] = @order.cancelled_at || now
        if @order.delivered_at.present?
          # Goods were delivered (cancelled out of a return/replacement flow): refunding here would pay the buyer
          # without recovering it from the seller's settlement. Use the refund endpoint (OrderRefundService).
          attrs[:status_note] = [attrs[:status_note], "Cancelled after delivery - refund must be issued via the refund action"].compact.join(" | ")
        else
          InstantOrderRefundService.process_refund!(order: @order, reason: @status_note.presence || "Order cancelled")
        end
      end

      @order.update!(attrs.compact)
      restock_cancelled_order!(previous_status) if next_status == "cancelled"
    end

    OrderSettlementService.process_if_due!(@order.reload)

    if @order.status == "shipped"
      EmailDispatcherService.retail_order_shipped(@order)
    elsif %w[delivered replacement_delivered].include?(@order.status)
      EmailDispatcherService.retail_order_delivered(@order)
    end

    @order
  end

  private

  # Accepting an order deducts the seller's listing stock (and Offer Mart reserves offer quantity at checkout);
  # nothing gave it back when the order was later cancelled, so inventory drifted down permanently.
  def restock_cancelled_order!(previous_status)
    if @order.dealer_offer_id.present?
      # Offer Mart: quantity is reserved from checkout (pending) until delivery.
      return unless previous_status == "pending" || RESTOCK_ON_CANCEL_FROM.include?(previous_status)

      @order.dealer_offer&.restore_quantity!(@order.total_items)
      return
    end

    return unless RESTOCK_ON_CANCEL_FROM.include?(previous_status)
    return if @order.seller_dealer_id.blank?

    @order.order_items.each do |item|
      next if item.dealer_product_id.blank?

      dealer_product = DealerProduct.lock.find_by(id: item.dealer_product_id, dealer_id: @order.seller_dealer_id)
      dealer_product&.restore_stock!(item.product_variant_color_id, item.quantity)
    end
  end
end
