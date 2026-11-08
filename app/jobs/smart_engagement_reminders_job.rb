class SmartEngagementRemindersJob < ApplicationJob
  queue_as :default

  REMINDER_HOURS = (9..20).freeze
  MORNING_HOURS = (9..11).freeze
  LOW_STOCK_LIMIT = 2
  MAX_CUSTOMER_REMINDERS_PER_RUN = 500

  def perform
    hour = Time.current.hour

    if REMINDER_HOURS.cover?(hour)
      send_delivery_review_reminders
      send_customer_missing_address_reminders
      send_customer_inactive_reminders
      send_dealer_dispatch_delay_reminders
      send_dealer_low_stock_alerts
      send_dealer_missing_bank_reminders
    end

    send_dealer_morning_briefing if MORNING_HOURS.cover?(hour)
  end

  private

  def each_record(scope, label)
    scope.find_each do |record|
      yield record
    rescue StandardError => e
      Rails.logger.warn("[SmartEngagementRemindersJob] #{label} failed for #{record.class.name}##{record.id}: #{e.class}: #{e.message}")
    end
  rescue StandardError => e
    Rails.logger.warn("[SmartEngagementRemindersJob] #{label} failed: #{e.class}: #{e.message}")
  end

  def already_sent?(receiver, kind, since: nil, notifiable: nil)
    scope = Notification.where(receiver: receiver, notification_type: kind)
    scope = scope.where(notifiable: notifiable) if notifiable
    scope = scope.where("notifications.created_at >= ?", since) if since
    scope.exists?
  end

  def recently_notified_ids(receiver_type, kind, since)
    Notification.where(receiver_type: receiver_type, notification_type: kind)
                .where("created_at >= ?", since)
                .select(:receiver_id)
  end

  def reachable_customers
    Account.where.not(status: %w[banned inactive])
  end

  def send_delivery_review_reminders
    orders = Order.where(status: "delivered", buyer_type: "Account")
                  .where(delivered_at: 48.hours.ago..24.hours.ago)
                  .includes(order_items: { product_variant: :product })

    each_record(orders, "delivery review reminder") do |order|
      account = order.buyer
      next unless account.present? && account.status.to_s != "banned"
      next if already_sent?(account, "delivery_review_reminder", notifiable: order)

      product_ids = order.order_items.filter_map { |item| item.product_variant&.product_id }
      next if product_ids.any? && Review.where(account_id: account.id, product_id: product_ids).exists?

      item_name = order.order_items.first&.product_name.presence || "item"
      NotificationService.deliver(
        recipient: account,
        kind: "delivery_review_reminder",
        title: "Kaisa raha aapka product? ⭐",
        message: "#{item_name.truncate(40)} ko rate karein aur apna review share karein.",
        notifiable: order,
        payload: { order_id: order.id, screen: "CustomerOrderDetails", role: "customer" }
      )
    end
  end

  def send_customer_missing_address_reminders
    accounts = reachable_customers
                 .where("accounts.created_at <= ?", 2.days.ago)
                 .where.missing(:addresses)
                 .where.not(id: recently_notified_ids("Account", "missing_address_reminder", 7.days.ago))
                 .limit(MAX_CUSTOMER_REMINDERS_PER_RUN)

    each_record(accounts, "missing address reminder") do |account|
      PushEventsHub.customer_missing_address_reminder(account)
    end
  end

  def send_customer_inactive_reminders
    recent_buyers = Order.where(buyer_type: "Account").where("orders.created_at >= ?", 7.days.ago).select(:buyer_id)
    accounts = reachable_customers
                 .where("accounts.created_at <= ?", 7.days.ago)
                 .where.not(id: recent_buyers)
                 .where.not(id: recently_notified_ids("Account", "inactive_customer_reminder", 14.days.ago))
                 .limit(MAX_CUSTOMER_REMINDERS_PER_RUN)

    each_record(accounts, "inactive customer reminder") do |account|
      PushEventsHub.customer_inactive_reminder(account)
    end
  end

  def send_dealer_dispatch_delay_reminders
    orders = Order.where(status: "processing")
                  .where.not(seller_dealer_id: nil)
                  .where(accepted_at: 2.days.ago..3.hours.ago)
                  .includes(:seller_dealer)

    each_record(orders, "dispatch delay reminder") do |order|
      dealer = order.seller_dealer
      next unless dealer&.active?
      next if already_sent?(dealer, "dispatch_delay_reminder", notifiable: order, since: 6.hours.ago)

      PushEventsHub.dealer_dispatch_delay_reminder(dealer, order)
    end
  end

  def send_dealer_morning_briefing
    each_record(Dealer.active, "morning briefing") do |dealer|
      next if already_sent?(dealer, "daily_morning_briefing", since: Time.current.beginning_of_day)

      summary = morning_summary_for(dealer)
      next if summary.values.sum.zero?

      PushEventsHub.dealer_daily_morning_briefing(dealer, summary)
    end
  end

  def morning_summary_for(dealer)
    listings = dealer.dealer_products.approved.where(is_active: true)
    stock = listings.pick(
      Arel.sql("COUNT(*)"),
      Arel.sql("COUNT(*) FILTER (WHERE stock_quantity <= 0)"),
      Arel.sql("COUNT(*) FILTER (WHERE stock_quantity > 0 AND stock_quantity <= #{LOW_STOCK_LIMIT})")
    ) || [0, 0, 0]

    retail_requests = OrderOffer.where(dealer_id: dealer.id, status: "open")
                                .joins(:order)
                                .where(orders: { status: "pending", seller_dealer_id: nil })
                                .count
    b2b_requests = B2bOrderOffer.where(dealer_id: dealer.id, status: "open")
                                .joins(:b2b_order)
                                .where(b2b_orders: { request_status: "pending_request" })
                                .count

    {
      to_dispatch: Order.where(seller_dealer_id: dealer.id, status: "processing").count,
      new_requests: retail_requests + b2b_requests,
      listings: stock[0].to_i,
      out_of_stock: stock[1].to_i,
      low_stock: stock[2].to_i
    }
  end

  def send_dealer_low_stock_alerts
    listings = DealerProduct.approved
                            .where(is_active: true, stock_quantity: 1..LOW_STOCK_LIMIT)
                            .includes(:dealer, :product)

    each_record(listings, "low stock alert") do |listing|
      dealer = listing.dealer
      product = listing.product
      next unless dealer&.active? && product

      next if already_sent?(dealer, "low_stock_alert", notifiable: product, since: 3.days.ago)

      PushEventsHub.dealer_low_stock_alert(dealer, product, listing.stock_quantity)
    end
  end

  def send_dealer_missing_bank_reminders
    dealers = Dealer.active
                    .left_joins(:dealer_profile)
                    .where("dealer_profiles.id IS NULL OR dealer_profiles.bank_account_number IS NULL OR dealer_profiles.bank_account_number = ''")
                    .where.not(id: recently_notified_ids("Dealer", "missing_bank_details_reminder", 7.days.ago))

    each_record(dealers, "missing bank reminder") do |dealer|
      PushEventsHub.dealer_missing_bank_reminder(dealer)
    end
  end
end
