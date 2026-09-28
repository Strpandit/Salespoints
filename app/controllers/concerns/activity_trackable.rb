module ActivityTrackable
  extend ActiveSupport::Concern

  # Human names for resources, used in log descriptions ("Approved wholesaler post 'X'").
  RESOURCE_NAMES = {
    "accounts" => "customer", "addresses" => "address", "admin_users" => "staff user", "admin_roles" => "staff role",
    "b2b_orders" => "B2B order", "brands" => "brand", "cat_filters" => "category filter", "categories" => "category",
    "contact_forms" => "contact form", "coupons" => "coupon", "dealer_addresses" => "dealer address",
    "dealer_ledger_entries" => "ledger entry", "dealer_notifications" => "dealer notification", "dealer_offers" => "Offer Mart offer",
    "dealer_orders" => "dealer order", "dealer_payouts" => "payout", "dealer_products" => "dealer product",
    "dealer_sessions" => "dealer session", "dealers" => "dealer", "deletion_requests" => "deletion request",
    "delivery_confirmations" => "delivery confirmation", "flash_sales" => "flash sale", "hero_slides" => "hero slide",
    "notifications" => "notification", "orders" => "order", "payments" => "payment", "products" => "product",
    "push_subscriptions" => "push subscription", "reports" => "report", "return_requests" => "return request",
    "reviews" => "review", "roles" => "role", "support_tickets" => "support ticket", "wholesaler_posts" => "wholesaler post"
  }.freeze

  # Past-tense verbs per controller action.
  ACTION_VERBS = {
    "create" => "Created", "update" => "Updated", "destroy" => "Deleted", "approve" => "Approved", "reject" => "Rejected",
    "toggle" => "Changed visibility of", "toggle_active" => "Changed visibility of", "block" => "Blocked", "unblock" => "Unblocked",
    "deactivate" => "Deactivated", "reactivate" => "Reactivated", "reorder" => "Reordered", "reupload" => "Re-uploaded",
    "buy" => "Placed order for", "buy_now" => "Placed order for", "rate" => "Rated", "cancel" => "Cancelled",
    "refund" => "Issued refund for", "release_settlement" => "Released settlement for", "download_invoice" => "Downloaded invoice of",
    "verify_bank_account" => "Verified bank account of", "approve_manual_bank_account" => "Approved bank account of",
    "approve_bank_change" => "Approved bank change for", "reject_bank_change" => "Rejected bank change for",
    "request_bank_change" => "Requested bank change for"
  }.freeze

  # GET endpoints that expose personal / KYC / bank data. Viewing them by staff is logged.
  SENSITIVE_VIEWS = {
    "dealers" => { "show" => "dealer profile (KYC & bank details)", "admin_overview" => "dealer overview",
                   "bank_change_requests" => "dealer bank change requests" },
    "admin_users" => { "show" => "staff profile" },
    "accounts" => { "show" => "customer profile" }
  }.freeze
  SENSITIVE_VIEW_DEDUP_WINDOW = 10.minutes

  EXPORT_ACTIONS = %w[download_invoice export_reports export_orders download_report].freeze
  SKIPPED_IVARS = %i[
    @_action_has_layout @_routes @_view_context_class @_lookup_context @_response @_request
    @current_user @current_user_type @activity_log_recorded
  ].freeze

  included do
    after_action :auto_track_activity, if: :should_auto_track_activity?
  end

  private

  def should_auto_track_activity?
    return false unless response.status.between?(200, 299)
    return false if activity_already_logged?
    return false if internal_exempt_controller?
    return false if current_user.blank?
    return true unless request.get? || request.head?

    EXPORT_ACTIONS.include?(action_name) || sensitive_view?
  end

  # Explicit ActivityLogger calls flag the request, so the automatic log doesn't duplicate them.
  def activity_already_logged?
    @activity_log_recorded || request.env[ActivityLogger::REQUEST_FLAG]
  end

  def internal_exempt_controller?
    # Notification read-receipts and push registrations are noise, not audit events.
    controller_name.in?(%w[activity_logs storefront analytics health pwa notifications dealer_notifications push_subscriptions])
  end

  def sensitive_view?
    current_user_type == "AdminUser" && SENSITIVE_VIEWS.dig(controller_name, action_name).present?
  end

  def auto_track_activity
    actor = current_user
    return if actor.blank?

    target = infer_target_entity
    return track_sensitive_view(actor, target) if request.get? && sensitive_view?

    changes = action_name == "create" ? {} : ActivityChangeSet.from(target)

    ActivityLogger.log(
      actor: actor,
      action: "#{controller_name.singularize}_#{action_name}",
      category: infer_category(controller_name),
      target: target,
      description: generate_auto_description(action_name, controller_name, target, changes),
      metadata: {
        controller: controller_name,
        action: action_name,
        status: response.status,
        changes: changes.presence,
        params: sanitized_request_params
      }.compact,
      request: request
    )
  rescue StandardError => e
    Rails.logger.warn("[ActivityTrackable] Auto-track error: #{e.message}")
  end

  def track_sensitive_view(actor, target)
    # Looking at your own staff profile isn't sensitive.
    return if controller_name == "admin_users" && target.is_a?(AdminUser) && target.id == actor.id

    # One entry per staff member + screen + record every few minutes (page refreshes aren't new events).
    recent = ActivityLog.where(actor_type: actor.class.name, actor_id: actor.id, action: "viewed_sensitive_data")
                        .where("created_at >= ?", SENSITIVE_VIEW_DEDUP_WINDOW.ago)
                        .where("activity_logs.metadata @> ?", { controller: controller_name, action: action_name }.to_json)
    recent = recent.where(target_type: target.class.name, target_id: target.id) if target
    return if recent.exists?

    label = SENSITIVE_VIEWS.dig(controller_name, action_name)
    name = target_label(target)
    ActivityLogger.log(
      actor: actor,
      action: "viewed_sensitive_data",
      category: "security",
      target: target,
      description: ["Viewed #{label}", name].compact.join(" of "),
      metadata: { controller: controller_name, action: action_name },
      request: request
    )
  end

  def sanitized_request_params
    sanitize_for_log(
      request.filtered_parameters.except("controller", "action", "format", "password", "password_confirmation", "current_password", "token")
    ).as_json
  end

  # Uploaded files serialise to their whole tempfile object; keep only a small descriptor.
  def sanitize_for_log(value)
    if value.respond_to?(:original_filename) && value.respond_to?(:content_type)
      return { file: value.original_filename, content_type: value.content_type, size: (value.size rescue nil) }
    end

    case value
    when ActionController::Parameters
      sanitize_for_log(value.to_unsafe_h)
    when Hash
      value.transform_values { |v| sanitize_for_log(v) }
    when Array
      value.first(50).map { |v| sanitize_for_log(v) }
    when String
      value.truncate(500)
    else
      value
    end
  end

  def infer_category(ctrl)
    case ctrl
    when /auth|session|password/ then "auth"
    when /dealer_products|inventory/ then "inventory"
    when /products|categories|brands|cat_filter|spec/ then "catalog"
    when /order|payment|payout|settlement|refund|ledger/ then "orders"
    when /offer/ then "offers"
    when /wholesaler/ then "wholesale"
    when /hero_slide|flash_sale|coupon/ then "marketing"
    when /admin|role|approv/ then "admin_action"
    when /account|dealer|address|kyc/ then "profile"
    when /ticket|support|contact/ then "support"
    when /review/ then "reviews"
    when /report/ then "reports"
    when /deletion/ then "security"
    else "settings"
    end
  end

  def infer_target_entity
    instance_variables.each do |var_name|
      next if var_name.in?(SKIPPED_IVARS)

      val = instance_variable_get(var_name)
      return val if val.is_a?(ActiveRecord::Base) && val.persisted?
    end
    nil
  end

  def target_label(target)
    return nil if target.blank?

    if target.respond_to?(:order_number) && target.order_number.present?
      "order ##{target.order_number}"
    elsif target.respond_to?(:reference_number) && target.try(:reference_number).present?
      "##{target.reference_number}"
    elsif target.respond_to?(:title) && target.title.present?
      "'#{target.title}'"
    elsif target.respond_to?(:highlight) && target.highlight.present?
      "'#{target.highlight}'"
    elsif target.respond_to?(:device_model) && target.device_model.present?
      "'#{target.device_model}'"
    elsif target.respond_to?(:dealer_code) && target.dealer_code.present?
      name = target.try(:dealer_profile)&.business_name.presence || target.try(:full_name).presence
      name ? "'#{name}' (#{target.dealer_code})" : "dealer #{target.dealer_code}"
    elsif target.respond_to?(:full_name) && target.full_name.present?
      "'#{target.full_name}'"
    elsif target.respond_to?(:name) && target.name.present?
      "'#{target.name}'"
    else
      "##{target.id}"
    end
  rescue StandardError
    "##{target&.id}"
  end

  def generate_auto_description(act, ctrl, target, changes = {})
    resource = RESOURCE_NAMES[ctrl] || ctrl.singularize.humanize(capitalize: false)
    verb = ACTION_VERBS[act]
    label = target_label(target)

    sentence =
      if verb
        [verb, resource, label].compact.join(" ")
      else
        "#{act.humanize} on #{[resource, label].compact.join(' ')}"
      end

    changed = ActivityChangeSet.summary(changes)
    changed ? "#{sentence} — changed #{changed}" : sentence
  end
end
