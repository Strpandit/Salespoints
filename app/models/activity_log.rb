class ActivityLog < ApplicationRecord
  belongs_to :actor, polymorphic: true, optional: true
  belongs_to :target, polymorphic: true, optional: true

  CATEGORIES = %w[auth catalog inventory orders offers wholesale kyc support admin_action reports settings profile security].freeze

  validates :actor_type, presence: true
  validates :actor_id, presence: true
  validates :action, presence: true
  validates :category, presence: true

  scope :for_dealers, -> { where(actor_type: "Dealer") }
  scope :for_staff, -> { where(actor_type: "AdminUser") }
  scope :for_customers, -> { where(actor_type: "Account") }
  scope :recent, -> { order(created_at: :desc) }

  scope :by_actor_type, ->(type) {
    case type.to_s.downcase
    when "dealer", "dealers"
      for_dealers
    when "staff", "admin", "admin_user", "adminuser", "admins"
      for_staff
    when "customer", "customers", "account", "accounts"
      for_customers
    else
      all
    end
  }

  scope :by_actor_id, ->(id) { where(actor_id: id) if id.present? }
  scope :by_category, ->(cat) { where(category: cat) if cat.present? && cat != "all" }
  scope :by_action, ->(act) { where(action: act) if act.present? && act != "all" }

  scope :by_date_range, ->(start_date, end_date) {
    scope = all
    if start_date.present?
      begin
        scope = scope.where("activity_logs.created_at >= ?", Time.zone.parse(start_date.to_s).beginning_of_day)
      rescue StandardError
        nil
      end
    end
    if end_date.present?
      begin
        scope = scope.where("activity_logs.created_at <= ?", Time.zone.parse(end_date.to_s).end_of_day)
      rescue StandardError
        nil
      end
    end
    scope
  }

  scope :search_query, ->(q) {
    return all if q.blank?
    term = "%#{q.strip}%"
    where(
      "actor_name ILIKE :term OR actor_email ILIKE :term OR action ILIKE :term OR target_title ILIKE :term OR description ILIKE :term OR ip_address ILIKE :term",
      term: term
    )
  }

  def human_time
    created_at.strftime("%d %b %Y, %I:%M %p")
  end
end
