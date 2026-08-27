class CreateReportAuditLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :report_audit_logs do |t|
      t.string :user_type, null: false
      t.bigint :user_id, null: false
      t.string :report_key, null: false
      t.string :format, null: false
      t.jsonb :applied_filters, default: {}, null: false
      t.integer :row_count, default: 0
      t.string :ip_address
      t.string :user_agent
      t.datetime :downloaded_at, null: false
      t.timestamps

      t.index :created_at
      t.index :report_key
      t.index [:user_type, :user_id]
    end
  end
end
