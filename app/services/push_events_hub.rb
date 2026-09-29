# frozen_string_literal: true

class PushEventsHub
  class << self
    # ──────────────────────────────────────────────────────────────────────────
    # SECTION A: CUSTOMER NOTIFICATIONS & REMINDERS
    # ──────────────────────────────────────────────────────────────────────────

    # 1. Direct Buy / B2C Order Placed
    def customer_order_placed(order)
      return unless order&.buyer
      NotificationService.deliver(
        recipient: order.buyer,
        kind: "b2c_order_placed",
        title: "Order Placed! 🎉",
        message: "Aapka Order ##{order.order_number} place ho gaya hai. Nearby dealer assign ho raha hai.",
        notifiable: order,
        payload: { order_id: order.id, screen: "CustomerOrderDetails", role: "customer" }
      )
    end

    # 2. Payment Confirmed (Cashfree)
    def customer_payment_success(order, amount = nil)
      return unless order&.buyer
      amt = amount || order.total_amount
      NotificationService.deliver(
        recipient: order.buyer,
        kind: "payment_success",
        title: "Payment Successful ✅",
        message: "₹#{amt} ka payment successfully confirm ho gaya hai Order ##{order.order_number} ke liye.",
        notifiable: order,
        payload: { order_id: order.id, screen: "CustomerOrderDetails", role: "customer" }
      )
    end

    # 3. Dealer Accepted Order
    def customer_order_accepted(order, dealer)
      return unless order&.buyer
      dealer_name = dealer&.store_name || dealer&.full_name || "Verified Dealer"
      NotificationService.deliver(
        recipient: order.buyer,
        kind: "order_accepted",
        title: "Dealer Assigned! 🏪",
        message: "#{dealer_name} ne aapka order accept kar liya hai aur packing start kar di hai.",
        notifiable: order,
        actor: dealer,
        payload: { order_id: order.id, screen: "CustomerOrderDetails", role: "customer" }
      )
    end

    # 4. Order Out for Delivery
    def customer_order_dispatched(order)
      return unless order&.buyer
      NotificationService.deliver(
        recipient: order.buyer,
        kind: "order_dispatched",
        title: "Out for Delivery 🚚",
        message: "Delivery partner Order ##{order.order_number} lekar aapke address ke liye nikal chuka hai.",
        notifiable: order,
        payload: { order_id: order.id, screen: "CustomerOrderDetails", role: "customer" }
      )
    end

    # 5. Delivery Completed
    def customer_order_delivered(order)
      return unless order&.buyer
      NotificationService.deliver(
        recipient: order.buyer,
        kind: "order_delivered",
        title: "Delivered Successfully 🎁",
        message: "Aapka Order ##{order.order_number} deliver ho chuka hai. Thank you for shopping with Salespoints!",
        notifiable: order,
        payload: { order_id: order.id, screen: "CustomerOrderDetails", role: "customer" }
      )
    end

    # 7. Order Cancelled / Expired
    def customer_order_cancelled(order, reason = nil)
      return unless order&.buyer
      msg = "Order ##{order.order_number} cancel ho gaya hai."
      msg += " Reason: #{reason}." if reason.present?
      msg += " Deducted amount 3-5 days me refund hoga."
      NotificationService.deliver(
        recipient: order.buyer,
        kind: "order_cancelled",
        title: "Order Cancelled ⚠️",
        message: msg,
        notifiable: order,
        payload: { order_id: order.id, screen: "CustomerOrderDetails", role: "customer" }
      )
    end

    # 9. OfferMart Deal Activated
    def customer_offermart_deal_active(account, deal)
      return unless account && deal
      NotificationService.deliver(
        recipient: account,
        kind: "offer_mart_deal_active",
        title: "New OfferMart Deal! 🔥",
        message: "#{deal.product_name} par Flat #{deal.discount_percent}% OFF start ho chuka hai. Limited stock!",
        notifiable: deal,
        payload: { deal_id: deal.id, screen: "OfferMartDetails" }
      )
    end

    # 10. Wishlist Item Price Drop
    def customer_price_drop(account, product, old_price, new_price)
      return unless account && product
      diff = (old_price - new_price).round
      NotificationService.deliver(
        recipient: account,
        kind: "wishlist_price_drop",
        title: "Price Drop Alert! 📉",
        message: "Aapke pasandeeda #{product.name} ka price ₹#{diff} kam ho gaya hai!",
        notifiable: product,
        payload: { product_id: product.id, screen: "ProductDetails" }
      )
    end

    # 11. OfferMart Deal Ending Soon
    def customer_offermart_ending_soon(account, deal)
      return unless account && deal
      NotificationService.deliver(
        recipient: account,
        kind: "offer_mart_ending_soon",
        title: "Only 2 Hours Left! ⏳",
        message: "#{deal.product_name} par OfferMart deal jald expire hone wali hai. Grab it now!",
        notifiable: deal,
        payload: { deal_id: deal.id, screen: "OfferMartDetails" }
      )
    end

    # 12. Item Back in Stock
    def customer_item_back_in_stock(account, product)
      return unless account && product
      NotificationService.deliver(
        recipient: account,
        kind: "item_back_in_stock",
        title: "Back in Stock! 📦",
        message: "#{product.name} ab wapas available hai. Turant order karein.",
        notifiable: product,
        payload: { product_id: product.id, screen: "ProductDetails" }
      )
    end

    # 13. Pincode Now Serviceable
    def customer_pincode_serviceable(account, product, pincode)
      return unless account && product
      NotificationService.deliver(
        recipient: account,
        kind: "pincode_now_serviceable",
        title: "Now Delivering to your Area! 📍",
        message: "#{product.name} ab aapke pincode (#{pincode}) par deliverable hai!",
        notifiable: product,
        payload: { product_id: product.id, screen: "ProductDetails" }
      )
    end

    # 14. Replacement Request Submitted
    def customer_replacement_requested(order)
      return unless order&.buyer
      NotificationService.deliver(
        recipient: order.buyer,
        kind: "replacement_requested",
        title: "Replacement Request Received 🔄",
        message: "Order ##{order.order_number} ke liye replacement request review me hai.",
        notifiable: order,
        payload: { order_id: order.id, screen: "CustomerOrderDetails", role: "customer" }
      )
    end

    # 15. Replacement Approved
    def customer_replacement_approved(order)
      return unless order&.buyer
      NotificationService.deliver(
        recipient: order.buyer,
        kind: "replacement_approved",
        title: "Replacement Approved! ✅",
        message: "Dealer replacement dispatch karne ki taiyari kar raha hai.",
        notifiable: order,
        payload: { order_id: order.id, screen: "CustomerOrderDetails", role: "customer" }
      )
    end

    # 16. Replacement Rejected
    def customer_replacement_rejected(order, reason = nil)
      return unless order&.buyer
      msg = "Replacement request for Order ##{order.order_number} accept nahi ho saki."
      msg += " Reason: #{reason}" if reason.present?
      NotificationService.deliver(
        recipient: order.buyer,
        kind: "replacement_rejected",
        title: "Replacement Update ℹ️",
        message: msg,
        notifiable: order,
        payload: { order_id: order.id, screen: "CustomerOrderDetails", role: "customer" }
      )
    end

    # 17. Replaced Item Dispatched
    def customer_replacement_dispatched(order)
      return unless order&.buyer
      NotificationService.deliver(
        recipient: order.buyer,
        kind: "replacement_dispatched",
        title: "Replaced Item Dispatched 🚚",
        message: "Aapka naya replacement item dispatch ho chuka hai.",
        notifiable: order,
        payload: { order_id: order.id, screen: "CustomerOrderDetails", role: "customer" }
      )
    end

    # 19. Support Ticket Reply
    def customer_ticket_replied(account, ticket)
      return unless account && ticket
      NotificationService.deliver(
        recipient: account,
        kind: "ticket_replied",
        title: "Support Team Replied 💬",
        message: "Aapke support ticket ##{ticket.id} par response aa gaya hai.",
        notifiable: ticket,
        payload: { ticket_id: ticket.id, screen: "Support", role: "customer" }
      )
    end

    # 20. Support Ticket Resolved
    def customer_ticket_resolved(account, ticket)
      return unless account && ticket
      NotificationService.deliver(
        recipient: account,
        kind: "ticket_resolved",
        title: "Ticket Resolved ✅",
        message: "Aapka query ticket ##{ticket.id} resolve mark kar diya gaya hai.",
        notifiable: ticket,
        payload: { ticket_id: ticket.id, screen: "Support", role: "customer" }
      )
    end

    # 21. Missing Address Reminder
    def customer_missing_address_reminder(account)
      return unless account
      NotificationService.deliver(
        recipient: account,
        kind: "missing_address_reminder",
        title: "Save Your Delivery Address 🏠",
        message: "Fast 1-tap ordering ke liye apna home/work address profile me save karein.",
        payload: { screen: "Addresses" }
      )
    end

    # 22. Inactive Customer Re-engagement
    def customer_inactive_reminder(account)
      return unless account
      NotificationService.deliver(
        recipient: account,
        kind: "inactive_customer_reminder",
        title: "Check What's New on Salespoints! 🌟",
        message: "Naye products aur exclusive local discounts live hain. Check them now!",
        payload: { screen: "CustomerTabs" }
      )
    end

    # 23. Festive / Seasonal Sale Alert
    def customer_festive_sale_alert(account, sale_title = "Mega Local Sale Live! 🎊")
      return unless account
      NotificationService.deliver(
        recipient: account,
        kind: "festive_sale_alert",
        title: sale_title,
        message: "Nearby verified dealers se best rates par purchase karein. Exclusive offers active!",
        payload: { screen: "CustomerTabs" }
      )
    end

    # 24. Security Alert (New Device Login)
    def customer_security_alert(account, ip_address = nil)
      return unless account
      msg = "Naye device se aapke account me login detect hua hai."
      msg += " IP: #{ip_address}." if ip_address.present?
      NotificationService.deliver(
        recipient: account,
        kind: "customer_security_alert",
        title: "Security Alert 🔒",
        message: msg,
        payload: { screen: "Security", priority: "high" }
      )
    end

    # 25. Profile Updated
    def customer_profile_updated(account)
      return unless account
      NotificationService.deliver(
        recipient: account,
        kind: "customer_profile_updated",
        title: "Profile Updated 📝",
        message: "Aapka account profile details successfully update ho gaya hai.",
        payload: { screen: "PersonalInfo" }
      )
    end

    # ──────────────────────────────────────────────────────────────────────────
    # SECTION B: DEALER NOTIFICATIONS & REMINDERS
    # ──────────────────────────────────────────────────────────────────────────

    # 26. 🚨 NEW B2C Broadcast Order (Urgent MAX Buzz)
    def dealer_b2c_order_broadcast(dealer, order, total_amount, item_name)
      return unless dealer && order
      NotificationService.deliver(
        recipient: dealer,
        kind: "b2c_order_broadcast",
        title: "NEW CUSTOMER ORDER! ⚡",
        message: "₹#{total_amount} ka naya order (#{item_name}) match hua hai. Tap to accept before others!",
        notifiable: order,
        payload: { order_id: order.id, screen: "DealerOrders", role: "dealer", priority: "high" }
      )
    end

    # 27. 🚨 NEW B2B Bulk Broadcast Order (Urgent MAX Buzz)
    def dealer_b2b_order_broadcast(dealer, order, qty, item_name)
      return unless dealer && order
      NotificationService.deliver(
        recipient: dealer,
        kind: "b2b_order_broadcast",
        title: "NEW B2B BULK ORDER! 💼",
        message: "#{qty} units ka B2B order inquiry (#{item_name}) aaya hai. Tap to review quotation!",
        notifiable: order,
        payload: { order_id: order.id, screen: "DealerB2BProducts", role: "dealer", priority: "high" }
      )
    end

    # 28. Broadcast Order Expiring in 2 Mins
    def dealer_order_expiring_soon(dealer, order)
      return unless dealer && order
      NotificationService.deliver(
        recipient: dealer,
        kind: "order_expiring_soon",
        title: "Order Expiring Soon! ⏰",
        message: "Order ##{order.order_number} sirf 2 minute me expire ho jayega. Claim now!",
        notifiable: order,
        payload: { order_id: order.id, screen: "DealerOrders", role: "dealer", priority: "high" }
      )
    end

    # 29. Order Claimed Successfully
    def dealer_order_assigned(dealer, order)
      return unless dealer && order
      NotificationService.deliver(
        recipient: dealer,
        kind: "order_assigned",
        title: "Order Assigned to You! 📦",
        message: "Order ##{order.order_number} aapko assign ho gaya hai. Item packing start karein.",
        notifiable: order,
        payload: { order_id: order.id, screen: "DealerOrderDetails", role: "dealer" }
      )
    end

    # 30. Dispatch Delay Reminder (3 Hours)
    def dealer_dispatch_delay_reminder(dealer, order)
      return unless dealer && order
      NotificationService.deliver(
        recipient: dealer,
        kind: "dispatch_delay_reminder",
        title: "Dispatch Pending ⏳",
        message: "Order ##{order.order_number} abhi tak dispatch nahi hua. On-time delivery metric ke liye dispatch karein.",
        notifiable: order,
        payload: { order_id: order.id, screen: "DealerOrderDetails", role: "dealer" }
      )
    end

    # 31. Customer Verified Delivery OTP
    def dealer_delivery_otp_verified(dealer, order)
      return unless dealer && order
      NotificationService.deliver(
        recipient: dealer,
        kind: "delivery_otp_verified",
        title: "Delivery Confirmed! 🏆",
        message: "Customer ne OTP verify kar diya. Order ##{order.order_number} delivery completed!",
        notifiable: order,
        payload: { order_id: order.id, screen: "DealerOrderDetails", role: "dealer" }
      )
    end

    # 32. Delivery Proof Approved
    def dealer_delivery_proof_approved(dealer, order)
      return unless dealer && order
      NotificationService.deliver(
        recipient: dealer,
        kind: "delivery_proof_approved",
        title: "Proof Accepted ✅",
        message: "Order ##{order.order_number} ka uploaded delivery proof verify ho gaya.",
        notifiable: order,
        payload: { order_id: order.id, screen: "DealerOrderDetails", role: "dealer" }
      )
    end

    # 33. Order Auto-Expired (No Dealer Accepted)
    def dealer_order_auto_expired(dealer, order)
      return unless dealer && order
      NotificationService.deliver(
        recipient: dealer,
        kind: "order_auto_expired",
        title: "Order Missed ⚠️",
        message: "Broadcast Order ##{order.order_number} timeout hone ki wajah se close ho gaya.",
        notifiable: order,
        payload: { screen: "DealerOrders", role: "dealer" }
      )
    end

    # 34. New Wholesaler Post Matched
    def dealer_wholesaler_post_matched(dealer, post)
      return unless dealer && post
      NotificationService.deliver(
        recipient: dealer,
        kind: "wholesaler_post_matched",
        title: "New Wholesaler Post! 📢",
        message: "#{post.title} ka fresh stock available hai best B2B rates par.",
        notifiable: post,
        payload: { wholesaler_post_id: post.id, screen: "DealerWholesalerFeed" }
      )
    end

    # 35. Wholesaler Post Expiring (24h)
    def dealer_wholesaler_post_expiring(dealer, post)
      return unless dealer && post
      NotificationService.deliver(
        recipient: dealer,
        kind: "wholesaler_post_expiring",
        title: "Post Expiring Tomorrow ⏱️",
        message: "Aapka wholesale post '#{post.title}' 24 ghante me expire hoga. Renew karein.",
        notifiable: post,
        payload: { wholesaler_post_id: post.id, screen: "DealerWholesalerFeed" }
      )
    end

    # 36. B2B Counter Offer Received
    def dealer_b2b_counter_offer_received(dealer, order, counter_rate)
      return unless dealer && order
      NotificationService.deliver(
        recipient: dealer,
        kind: "b2b_counter_offer_received",
        title: "Counter Offer Received 💬",
        message: "B2B Order ##{order.order_number} par buyer ne ₹#{counter_rate}/unit ka counter offer diya hai.",
        notifiable: order,
        payload: { order_id: order.id, screen: "DealerB2BProductDetails", role: "dealer" }
      )
    end

    # 37. B2B Quotation Accepted
    def dealer_b2b_offer_accepted(dealer, order)
      return unless dealer && order
      NotificationService.deliver(
        recipient: dealer,
        kind: "b2b_offer_accepted",
        title: "B2B Offer Accepted! 🎉",
        message: "Buyer ne aapka B2B quotation accept kar liya hai Order ##{order.order_number} ke liye.",
        notifiable: order,
        payload: { order_id: order.id, screen: "DealerOrders", role: "dealer" }
      )
    end

    # 38. B2B Payment Deposited into Escrow
    def dealer_b2b_escrow_secured(dealer, order)
      return unless dealer && order
      NotificationService.deliver(
        recipient: dealer,
        kind: "b2b_escrow_secured",
        title: "Payment Secured 💰",
        message: "Order ##{order.order_number} ka payment lock ho chuka hai. Safely dispatch karein.",
        notifiable: order,
        payload: { order_id: order.id, screen: "DealerOrderDetails", role: "dealer" }
      )
    end

    # 39. Unanswered B2B Inquiry (4h Reminder)
    def dealer_unanswered_b2b_inquiry(dealer, order)
      return unless dealer && order
      NotificationService.deliver(
        recipient: dealer,
        kind: "unanswered_b2b_inquiry_reminder",
        title: "Buyer Awaiting Reply ⏳",
        message: "B2B Buyer Order ##{order.order_number} par aapke quotation ka intezaar kar raha hai.",
        notifiable: order,
        payload: { order_id: order.id, screen: "DealerB2BProducts", role: "dealer" }
      )
    end

    # 40. Daily/Weekly Settlement Credited
    def dealer_payout_credited(dealer, payout)
      return unless dealer && payout
      NotificationService.deliver(
        recipient: dealer,
        kind: "dealer_payout_credited",
        title: "Payout Credited! 💸",
        message: "₹#{payout.amount} aapke registered bank account me transfer ho gaya hai.",
        notifiable: payout,
        payload: { screen: "DealerPayments" }
      )
    end

    # 41. Payout Processing / Initiated
    def dealer_payout_processing(dealer, payout)
      return unless dealer && payout
      NotificationService.deliver(
        recipient: dealer,
        kind: "dealer_payout_processing",
        title: "Payout Initiated 🏦",
        message: "₹#{payout.amount} ka payout batch processing me chala gaya hai.",
        notifiable: payout,
        payload: { screen: "DealerPayments" }
      )
    end

    # 42. Bank Account Change Approved
    def dealer_bank_change_approved(dealer)
      return unless dealer
      NotificationService.deliver(
        recipient: dealer,
        kind: "bank_change_approved",
        title: "Bank Details Verified ✅",
        message: "Admin dwara aapki nayi bank details approve kar di gayi hain.",
        notifiable: dealer,
        payload: { screen: "DealerProfileEdit" }
      )
    end

    # 43. Bank Account Change Rejected
    def dealer_bank_change_rejected(dealer, reason = nil)
      return unless dealer
      msg = "Bank details update reject ho gayi."
      msg += " Reason: #{reason}" if reason.present?
      NotificationService.deliver(
        recipient: dealer,
        kind: "bank_change_rejected",
        title: "Bank Update Rejected ❌",
        message: msg,
        notifiable: dealer,
        payload: { screen: "DealerProfileEdit" }
      )
    end

    # 44. Missing Bank Details Reminder
    def dealer_missing_bank_reminder(dealer)
      return unless dealer
      NotificationService.deliver(
        recipient: dealer,
        kind: "missing_bank_details_reminder",
        title: "Add Bank Details 💳",
        message: "Order payouts prapt karne ke liye apni bank details update karein.",
        notifiable: dealer,
        payload: { screen: "DealerProfileEdit" }
      )
    end

    # 45. Low Stock Alert (<= 2 Units)
    def dealer_low_stock_alert(dealer, product, remaining_qty)
      return unless dealer && product
      NotificationService.deliver(
        recipient: dealer,
        kind: "low_stock_alert",
        title: "Low Stock Warning 📉",
        message: "#{product.name} ka stock sirf #{remaining_qty} bacha hai. Re-stock karein.",
        notifiable: product,
        payload: { product_id: product.id, screen: "DealerProducts" }
      )
    end

    # 46. Out of Stock Alert
    def dealer_out_of_stock_alert(dealer, product)
      return unless dealer && product
      NotificationService.deliver(
        recipient: dealer,
        kind: "out_of_stock_alert",
        title: "Product Out of Stock 🔴",
        message: "#{product.name} out of stock ho gaya hai. Listings temporary pause ho gayi hain.",
        notifiable: product,
        payload: { product_id: product.id, screen: "DealerProducts" }
      )
    end

    # 47. Custom Product Approved by Admin
    def dealer_custom_product_approved(dealer, product)
      return unless dealer && product
      NotificationService.deliver(
        recipient: dealer,
        kind: "custom_product_approved",
        title: "Custom Product Live! 🚀",
        message: "Aapka product '#{product.name}' admin dwara approve ho gaya hai.",
        notifiable: product,
        payload: { product_id: product.id, screen: "DealerProducts" }
      )
    end

    # 48. Custom Product Rejected
    def dealer_custom_product_rejected(dealer, product, reason = nil)
      return unless dealer && product
      msg = "Product '#{product.name}' review guidelines meet nahi kar paya."
      msg += " Reason: #{reason}" if reason.present?
      NotificationService.deliver(
        recipient: dealer,
        kind: "custom_product_rejected",
        title: "Product Review Update ℹ️",
        message: msg,
        notifiable: product,
        payload: { product_id: product.id, screen: "DealerProducts" }
      )
    end

    # 49. Morning Business Summary (9:00 AM)
    def dealer_daily_morning_briefing(dealer, pending_count)
      return unless dealer
      NotificationService.deliver(
        recipient: dealer,
        kind: "daily_morning_briefing",
        title: "Suprabhat! ☀️ Aaj ka Business Snapshot",
        message: "Aapke paas #{pending_count} active orders fulfill karne ke liye ready hain.",
        notifiable: dealer,
        payload: { screen: "DealerOrders", role: "dealer" }
      )
    end

    # 50. Customer Replacement Received
    def dealer_replacement_received(dealer, order)
      return unless dealer && order
      NotificationService.deliver(
        recipient: dealer,
        kind: "dealer_replacement_received",
        title: "Replacement Request! 🔄",
        message: "Customer ne Order ##{order.order_number} ke liye replacement request create ki hai.",
        notifiable: order,
        payload: { order_id: order.id, screen: "DealerOrderDetails", role: "dealer", priority: "high" }
      )
    end

    # 51. Dealer Store Verified
    def dealer_store_verified(dealer)
      return unless dealer
      NotificationService.deliver(
        recipient: dealer,
        kind: "dealer_store_verified",
        title: "Store Verification Complete 🛡️",
        message: "Aapka dealer account verify ho chuka hai. Happy selling on Salespoints!",
        notifiable: dealer,
        payload: { screen: "DealerDashboard" }
      )
    end

    # 52. Dealer Security Alert (New Login)
    def dealer_security_alert(dealer, ip_address = nil)
      return unless dealer
      msg = "Naye device se dealer portal login detect hua hai."
      msg += " IP: #{ip_address}." if ip_address.present?
      NotificationService.deliver(
        recipient: dealer,
        kind: "dealer_security_alert",
        title: "Security Alert 🔒",
        message: msg,
        notifiable: dealer,
        payload: { screen: "DealerProfile", priority: "high" }
      )
    end
  end
end
