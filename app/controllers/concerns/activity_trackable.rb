module ActivityTrackable
  extend ActiveSupport::Concern

  included do
    after_action :auto_track_activity, if: :should_auto_track_activity?
  end

  private

  def should_auto_track_activity?
    # Only track successful requests (HTTP 200-299)
    return false unless response.status.between?(200, 299)
    # Only track mutating HTTP methods (POST, PUT, PATCH, DELETE) or explicitly tracked GET actions
    return false if request.get? && !tracked_get_actions.include?(action_name)
    return false if @activity_log_recorded
    return false if internal_exempt_controller?

    current_user.present?
  end

  def internal_exempt_controller?
    controller_name.in?(%w[activity_logs storefront analytics health pwa])
  end

  def tracked_get_actions
    %w[download_invoice export_reports export_orders download_report]
  end

  def auto_track_activity
    actor = current_user
    return if actor.blank?

    cat = infer_category(controller_name)
    action_key = "#{controller_name.singularize}_#{action_name}"
    target = infer_target_entity
    desc = generate_auto_description(actor, action_name, controller_name, target)

    sanitized_params = request.filtered_parameters.except("controller", "action", "format", "password", "password_confirmation", "current_password", "token")

    ActivityLogger.log(
      actor: actor,
      action: action_key,
      category: cat,
      target: target,
      description: desc,
      metadata: {
        controller: controller_name,
        action: action_name,
        status: response.status,
        params: sanitized_params.as_json
      },
      request: request
    )
  rescue StandardError => e
    Rails.logger.warn("[ActivityTrackable] Auto-track error: #{e.message}")
  end

  def infer_category(ctrl)
    case ctrl
    when /auth|session|password/ then "auth"
    when /products|categories|brands|cat_filter|spec/ then "catalog"
    when /dealer_products|inventory/ then "inventory"
    when /order|payment|payout|settlement|refund/ then "orders"
    when /offer/ then "offers"
    when /wholesaler/ then "wholesale"
    when /account|dealer|address|kyc/ then "profile"
    when /admin|role|approv/ then "admin_action"
    when /ticket|support|contact/ then "support"
    when /review/ then "reviews"
    when /coupon/ then "marketing"
    when /report/ then "reports"
    when /deletion/ then "security"
    else "settings"
    end
  end

  def infer_target_entity
    instance_variables.each do |var_name|
      next if var_name.in?(%i[@_action_has_layout @_routes @_view_context_class @_lookup_context @_response @_request @current_user @current_user_type @activity_log_recorded])
      val = instance_variable_get(var_name)
      if val.is_a?(ActiveRecord::Base) && val.persisted?
        return val
      end
    end
    nil
  end

  def generate_auto_description(actor, act, ctrl, target)
    resource = ctrl.singularize.humanize
    target_name = if target.present?
                    if target.respond_to?(:title) && target.title.present?
                      "'#{target.title}'"
                    elsif target.respond_to?(:name) && target.name.present?
                      "'#{target.name}'"
                    elsif target.respond_to?(:order_number) && target.order_number.present?
                      "Order ##{target.order_number}"
                    elsif target.respond_to?(:device_model) && target.device_model.present?
                      "'#{target.device_model}'"
                    elsif target.respond_to?(:dealer_code) && target.dealer_code.present?
                      "Dealer #{target.dealer_code}"
                    else
                      "##{target.id}"
                    end
                  else
                    ""
                  end

    case act
    when "create"
      "Created new #{resource} #{target_name}".strip
    when "update"
      "Updated #{resource} #{target_name}".strip
    when "destroy"
      "Deleted #{resource} #{target_name}".strip
    when "approve"
      "Approved #{resource} #{target_name}".strip
    when "reject"
      "Rejected #{resource} #{target_name}".strip
    when "toggle", "toggle_active"
      "Toggled status of #{resource} #{target_name}".strip
    when "block"
      "Blocked #{resource} #{target_name}".strip
    when "unblock"
      "Unblocked #{resource} #{target_name}".strip
    when "download_invoice"
      "Downloaded tax invoice #{target_name}".strip
    when "verify_bank_account"
      "Verified bank details for #{resource} #{target_name}".strip
    when "refund"
      "Issued refund for #{target_name}".strip
    when "release_settlement"
      "Released payout settlement for #{target_name}".strip
    else
      "Performed #{act.humanize.downcase} on #{resource} #{target_name}".strip
    end
  end
end
