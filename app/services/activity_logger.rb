class ActivityLogger
  class << self
    def log(actor:, action:, category:, target: nil, target_title: nil, description: nil, metadata: {}, request: nil, platform: nil)
      return if actor.blank?

      actor_info = resolve_actor_info(actor)
      request_info = resolve_request_info(request)

      resolved_platform = platform.presence || request_info[:platform] || "web"
      resolved_target_title = target_title.presence || resolve_target_title(target)

      ActivityLog.create!(
        actor_type: actor.class.name,
        actor_id: actor.id,
        actor_name: actor_info[:name],
        actor_email: actor_info[:email],
        actor_role: actor_info[:role],
        action: action.to_s,
        category: category.to_s,
        target_type: target&.class&.name,
        target_id: target&.id,
        target_title: resolved_target_title,
        description: description.presence || generate_default_description(actor_info[:name], action, resolved_target_title),
        ip_address: request_info[:ip_address],
        user_agent: request_info[:user_agent],
        platform: resolved_platform,
        metadata: (metadata || {}).as_json
      )
    rescue StandardError => e
      Rails.logger.error("[ActivityLogger] Error logging activity: #{e.message}\n#{e.backtrace&.first(3)&.join("\n")}")
      nil
    end

    # Convenience method for Auth activities
    def log_auth(actor:, action:, request: nil, details: {})
      category = "auth"
      desc = case action.to_s
             when "login" then "Logged in to the platform"
             when "logout" then "Logged out of the platform"
             when "signup" then "Created a new account"
             when "verify_otp" then "Verified phone / email OTP"
             when "change_password" then "Changed account password"
             when "reset_password" then "Reset forgotten password"
             else "Authentication action: #{action}"
             end

      log(
        actor: actor,
        action: action,
        category: category,
        description: desc,
        metadata: details,
        request: request
      )
    end

    # Convenience method for Catalog / Products
    def log_catalog(actor:, action:, target:, description: nil, metadata: {}, request: nil)
      log(
        actor: actor,
        action: action,
        category: "catalog",
        target: target,
        description: description,
        metadata: metadata,
        request: request
      )
    end

    # Convenience method for Orders
    def log_order(actor:, action:, target:, description: nil, metadata: {}, request: nil)
      log(
        actor: actor,
        action: action,
        category: "orders",
        target: target,
        description: description,
        metadata: metadata,
        request: request
      )
    end

    # Convenience method for Admin actions
    def log_admin(actor:, action:, target: nil, target_title: nil, description: nil, metadata: {}, request: nil)
      log(
        actor: actor,
        action: action,
        category: "admin_action",
        target: target,
        target_title: target_title,
        description: description,
        metadata: metadata,
        request: request
      )
    end

    private

    def resolve_actor_info(actor)
      case actor
      when Dealer
        name = actor.dealer_profile&.business_name.presence ||
               "#{actor.first_name} #{actor.last_name}".strip.presence ||
               "Dealer (#{actor.dealer_code})"
        {
          name: name,
          email: actor.email,
          role: "dealer"
        }
      when AdminUser
        name = actor.name.presence || actor.email
        role = actor.super_admin? ? "super_admin" : (actor.roles.pluck(:name).join(", ").presence || "staff")
        {
          name: name,
          email: actor.email,
          role: role
        }
      when Account
        name = "#{actor.first_name} #{actor.last_name}".strip.presence ||
               actor.phone.presence ||
               actor.email.presence ||
               "Customer ##{actor.id}"
        {
          name: name,
          email: actor.email.presence || actor.phone,
          role: "customer"
        }
      else
        {
          name: actor.respond_to?(:name) ? actor.name : "#{actor.class.name} ##{actor.id}",
          email: actor.respond_to?(:email) ? actor.email : nil,
          role: actor.class.name.underscore
        }
      end
    end

    def resolve_request_info(request)
      return { ip_address: nil, user_agent: nil, platform: "web" } if request.blank?

      ip = request.respond_to?(:remote_ip) ? request.remote_ip : request.ip
      ua = request.user_agent.to_s
      header_platform = request.headers["X-Client-Platform"]&.downcase

      platform = if header_platform.present?
                   header_platform
                 elsif ua.match?(/okhttp|dart|expo|reactnative|salespoints-mobile/i)
                   ua.match?(/ios|iphone|ipad/i) ? "mobile_ios" : "mobile_android"
                 elsif ua.match?(/mobile|android|iphone|ipad/i)
                   "mobile_web"
                 else
                   "web"
                 end

      {
        ip_address: ip,
        user_agent: ua.truncate(500),
        platform: platform
      }
    end

    def resolve_target_title(target)
      return nil if target.blank?

      if target.respond_to?(:title) && target.title.present?
        target.title
      elsif target.respond_to?(:name) && target.name.present?
        target.name
      elsif target.respond_to?(:order_number) && target.order_number.present?
        "Order ##{target.order_number}"
      elsif target.respond_to?(:device_model) && target.device_model.present?
        target.device_model
      elsif target.respond_to?(:dealer_code) && target.dealer_code.present?
        "Dealer #{target.dealer_code}"
      elsif target.respond_to?(:subject) && target.subject.present?
        target.subject
      else
        "#{target.class.name} ##{target.id}"
      end
    rescue StandardError
      "#{target.class.name} ##{target.id}"
    end

    def generate_default_description(actor_name, action, target_title)
      action_clean = action.to_s.humanize.downcase
      if target_title.present?
        "#{actor_name} #{action_clean} #{target_title}"
      else
        "#{actor_name} performed #{action_clean}"
      end
    end
  end
end
