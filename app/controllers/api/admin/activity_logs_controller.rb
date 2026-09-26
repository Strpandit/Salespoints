module Api
  module Admin
    class ActivityLogsController < Api::ApplicationController
      before_action :require_super_admin!

      # GET /api/admin/activity_logs
      def index
        logs = ActivityLog.recent

        if params[:actor_type].present? && params[:actor_type] != "all"
          logs = logs.by_actor_type(params[:actor_type])
        end

        if params[:actor_id].present? && params[:actor_id] != "all"
          logs = logs.by_actor_id(params[:actor_id])
        end

        if params[:category].present? && params[:category] != "all"
          logs = logs.by_category(params[:category])
        end

        if params[:action_name].present? && params[:action_name] != "all"
          logs = logs.by_action(params[:action_name])
        elsif params[:action].present? && params[:action] != "all"
          logs = logs.by_action(params[:action])
        end

        if params[:platform].present? && params[:platform] != "all"
          logs = logs.where(platform: params[:platform])
        end

        if params[:start_date].present? || params[:end_date].present?
          logs = logs.by_date_range(params[:start_date], params[:end_date])
        end

        if params[:search].present?
          logs = logs.search_query(params[:search])
        end

        page = (params[:page] || 1).to_i
        per_page = (params[:per_page] || 25).to_i

        paginated = logs.page(page).per(per_page)

        render json: {
          data: paginated.map { |log| ActivityLogSerializer.render(log) },
          meta: {
            current_page: paginated.current_page,
            next_page: paginated.next_page,
            prev_page: paginated.prev_page,
            total_pages: paginated.total_pages,
            total_count: paginated.total_count
          }
        }, status: :ok
      end

      # GET /api/admin/activity_logs/actors
      # Returns a list of users for a given actor_type to populate the user selector / sidebar
      def actors
        actor_type = params[:actor_type].to_s.downcase
        search = params[:search].to_s.strip

        list = case actor_type
               when "dealer", "dealers"
                 dealers_scope(search)
               when "staff", "admin", "admin_user", "adminuser", "admins"
                 staff_scope(search)
               when "customer", "customers", "account", "accounts"
                 customers_scope(search)
               else
                 []
               end

        render json: { data: list }, status: :ok
      end

      # GET /api/admin/activity_logs/stats
      def stats
        today_start = Time.zone.now.beginning_of_day

        render json: {
          data: {
            total_logs: ActivityLog.count,
            dealer_logs_count: ActivityLog.for_dealers.count,
            staff_logs_count: ActivityLog.for_staff.count,
            customer_logs_count: ActivityLog.for_customers.count,
            today_logs_count: ActivityLog.where("created_at >= ?", today_start).count,
            categories: ActivityLog::CATEGORIES,
            category_counts: ActivityLog.group(:category).count
          }
        }, status: :ok
      end

      # GET /api/admin/activity_logs/:id
      def show
        log = ActivityLog.find_by(id: params[:id])
        return render json: { error: "Activity log not found" }, status: :not_found unless log

        render json: { data: ActivityLogSerializer.render(log) }, status: :ok
      end

      private

      def require_super_admin!
        unless current_admin&.super_admin?
          render json: { error: "Access denied. Only Super Admin can access Activity Logs." }, status: :forbidden
        end
      end

      def dealers_scope(search)
        scope = Dealer.includes(:dealer_profile).order(created_at: :desc)
        if search.present?
          term = "%#{search}%"
          scope = scope.joins("LEFT JOIN dealer_profiles ON dealer_profiles.dealer_id = dealers.id").where(
            "dealers.first_name ILIKE :term OR dealers.last_name ILIKE :term OR dealers.email ILIKE :term OR dealers.phone ILIKE :term OR dealers.dealer_code ILIKE :term OR dealer_profiles.business_name ILIKE :term",
            term: term
          )
        end

        counts = ActivityLog.for_dealers.group(:actor_id).count
        last_activities = ActivityLog.for_dealers.group(:actor_id).maximum(:created_at)

        scope.limit(100).map do |d|
          name = d.dealer_profile&.business_name.presence || "#{d.first_name} #{d.last_name}".strip.presence || "Dealer ##{d.id}"
          {
            id: d.id,
            actor_type: "Dealer",
            name: name,
            code: d.dealer_code,
            email: d.email,
            phone: d.phone,
            role: "dealer",
            status: d.status,
            total_activities: counts[d.id] || 0,
            last_activity_at: last_activities[d.id]
          }
        end
      end

      def staff_scope(search)
        scope = AdminUser.includes(:roles).order(created_at: :desc)
        if search.present?
          term = "%#{search}%"
          scope = scope.where("name ILIKE :term OR email ILIKE :term", term: term)
        end

        counts = ActivityLog.for_staff.group(:actor_id).count
        last_activities = ActivityLog.for_staff.group(:actor_id).maximum(:created_at)

        scope.limit(100).map do |u|
          role_label = u.super_admin? ? "Super Admin" : (u.roles.pluck(:name).join(", ").presence || "Staff")
          {
            id: u.id,
            actor_type: "AdminUser",
            name: u.name.presence || u.email,
            email: u.email,
            role: role_label,
            is_super_admin: u.super_admin?,
            status: u.is_active ? "active" : "inactive",
            total_activities: counts[u.id] || 0,
            last_activity_at: last_activities[u.id]
          }
        end
      end

      def customers_scope(search)
        scope = Account.order(created_at: :desc)
        if search.present?
          term = "%#{search}%"
          scope = scope.where("first_name ILIKE :term OR last_name ILIKE :term OR email ILIKE :term OR phone ILIKE :term", term: term)
        end

        counts = ActivityLog.for_customers.group(:actor_id).count
        last_activities = ActivityLog.for_customers.group(:actor_id).maximum(:created_at)

        scope.limit(100).map do |c|
          name = "#{c.first_name} #{c.last_name}".strip.presence || c.phone.presence || c.email.presence || "Customer ##{c.id}"
          {
            id: c.id,
            actor_type: "Account",
            name: name,
            email: c.email,
            phone: c.phone,
            role: "customer",
            status: c.status,
            total_activities: counts[c.id] || 0,
            last_activity_at: last_activities[c.id]
          }
        end
      end
    end
  end
end
