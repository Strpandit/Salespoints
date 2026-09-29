# frozen_string_literal: true

class SmartEngagementRemindersJob < ApplicationJob
  queue_as :default

  def perform
    # 1. Customer Reminders
    send_delivery_review_reminders
    send_customer_missing_address_reminders
    send_customer_inactive_reminders

    # 2. Dealer Reminders & Operational Alerts
    send_dealer_dispatch_delay_reminders
    send_dealer_morning_briefing if morning_time?
    send_dealer_low_stock_alerts
    send_dealer_missing_bank_reminders
  end

  private

  def morning_time?
    Time.current.hour == 9
  end

  # Customer: Order delivered > 24 hours ago, no review given yet
  def send_delivery_review_reminders
    recent_delivered = Order.where(status: "delivered")
                            .where("delivered_at >= ? AND delivered_at <= ?", 48.hours.ago, 24.hours.ago)

    recent_delivered.find_each do |order|
      next unless order.buyer.present?
      next if order.reviews.exists?
      next if Notification.where(receiver: order.buyer, notifiable: order, notification_type: "delivery_review_reminder").exists?

      item_name = order.order_items.first&.product&.name || "item"
      NotificationService.deliver(
        recipient: order.buyer,
        kind: "delivery_review_reminder",
        title: "Kaisa raha aapka product? ⭐",
        message: "#{item_name.truncate(40)} ko rate karein aur apna review share karein.",
        notifiable: order,
        payload: { order_id: order.id, screen: "CustomerOrderDetails", role: "customer" }
      )
    end
  rescue StandardError => e
    Rails.logger.warn("[SmartEngagementRemindersJob] send_delivery_review_reminders failed: #{e.message}")
  end

  # Customer: Accounts created > 2 days ago without any saved addresses
  def send_customer_missing_address_reminders
    Account.where("created_at <= ?", 2.days.ago).find_each do |account|
      next if account.addresses.exists?
      next if Notification.where(receiver: account, notification_type: "missing_address_reminder")
                          .where("created_at >= ?", 7.days.ago).exists?

      PushEventsHub.customer_missing_address_reminder(account)
    end
  rescue StandardError => e
    Rails.logger.warn("[SmartEngagementRemindersJob] send_customer_missing_address_reminders failed: #{e.message}")
  end

  # Customer: Inactive customers (> 7 days without orders)
  def send_customer_inactive_reminders
    Account.where("created_at <= ?", 7.days.ago).find_each do |account|
      has_recent_orders = Order.where(buyer: account).where("created_at >= ?", 7.days.ago).exists?
      next if has_recent_orders
      next if Notification.where(receiver: account, notification_type: "inactive_customer_reminder")
                          .where("created_at >= ?", 14.days.ago).exists?

      PushEventsHub.customer_inactive_reminder(account)
    end
  rescue StandardError => e
    Rails.logger.warn("[SmartEngagementRemindersJob] send_customer_inactive_reminders failed: #{e.message}")
  end

  # Dealer: Assigned orders waiting for dispatch > 3 hours
  def send_dealer_dispatch_delay_reminders
    delayed_orders = Order.where(status: ["assigned", "processing"])
                          .where("updated_at <= ?", 3.hours.ago)

    delayed_orders.find_each do |order|
      dealer = order.dealer
      next unless dealer
      next if Notification.where(receiver: dealer, notifiable: order, notification_type: "dispatch_delay_reminder")
                          .where("created_at >= ?", 6.hours.ago).exists?

      PushEventsHub.dealer_dispatch_delay_reminder(dealer, order)
    end
  rescue StandardError => e
    Rails.logger.warn("[SmartEngagementRemindersJob] send_dealer_dispatch_delay_reminders failed: #{e.message}")
  end

  # Dealer: Daily Morning Business Briefing at 9:00 AM
  def send_dealer_morning_briefing
    Dealer.where(status: "approved").find_each do |dealer|
      pending_orders_count = Order.where(dealer_id: dealer.id, status: ["assigned", "processing"]).count
      next if pending_orders_count.zero?
      next if Notification.where(receiver: dealer, notification_type: "daily_morning_briefing")
                          .where("created_at >= ?", Time.current.beginning_of_day).exists?

      PushEventsHub.dealer_daily_morning_briefing(dealer, pending_orders_count)
    end
  rescue StandardError => e
    Rails.logger.warn("[SmartEngagementRemindersJob] send_dealer_morning_briefing failed: #{e.message}")
  end

  # Dealer: Low Stock Alert (<= 2 units left)
  def send_dealer_low_stock_alerts
    DealerInventory.where("stock_quantity <= ? AND stock_quantity > ?", 2, 0).find_each do |inv|
      dealer = inv.dealer
      next unless dealer&.status == "approved"
      product = inv.product
      next unless product
      next if Notification.where(receiver: dealer, notifiable: product, notification_type: "low_stock_alert")
                          .where("created_at >= ?", 3.days.ago).exists?

      PushEventsHub.dealer_low_stock_alert(dealer, product, inv.stock_quantity)
    end
  rescue StandardError => e
    Rails.logger.warn("[SmartEngagementRemindersJob] send_dealer_low_stock_alerts failed: #{e.message}")
  end

  # Dealer: Missing Bank Details Reminder
  def send_dealer_missing_bank_reminders
    Dealer.where(status: "approved").where(bank_account_number: [nil, ""]).find_each do |dealer|
      next if Notification.where(receiver: dealer, notification_type: "missing_bank_details_reminder")
                          .where("created_at >= ?", 7.days.ago).exists?

      PushEventsHub.dealer_missing_bank_reminder(dealer)
    end
  rescue StandardError => e
    Rails.logger.warn("[SmartEngagementRemindersJob] send_dealer_missing_bank_reminders failed: #{e.message}")
  end
end
