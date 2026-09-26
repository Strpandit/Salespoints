class ActivityLogSerializer < ApplicationSerializer
  attributes :id, :actor_type, :actor_id, :actor_name, :actor_email, :actor_role, :action, :category, :target_type, :target_id, :target_title, :description, :ip_address, :user_agent, :platform, :metadata, :created_at

  attribute :human_time do |log|
    log.human_time
  end
end
