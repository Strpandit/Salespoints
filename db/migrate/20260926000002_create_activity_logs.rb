class CreateActivityLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :activity_logs do |t|
      t.string :actor_type, null: false
      t.bigint :actor_id, null: false
      t.string :actor_name
      t.string :actor_email
      t.string :actor_role
      t.string :action, null: false
      t.string :category, null: false
      t.string :target_type
      t.bigint :target_id
      t.string :target_title
      t.text :description
      t.string :ip_address
      t.string :user_agent
      t.string :platform, default: "web"
      t.jsonb :metadata, default: {}

      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
    end

    add_index :activity_logs, [:actor_type, :actor_id, :created_at], name: "idx_activity_logs_on_actor"
    add_index :activity_logs, [:category, :created_at], name: "idx_activity_logs_on_category"
    add_index :activity_logs, [:action, :created_at], name: "idx_activity_logs_on_action"
    add_index :activity_logs, [:target_type, :target_id], name: "idx_activity_logs_on_target"
    add_index :activity_logs, :created_at, name: "idx_activity_logs_on_created_at"
  end
end
