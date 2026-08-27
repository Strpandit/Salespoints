class CreateSupportTickets < ActiveRecord::Migration[8.0]
  def change
    create_table :support_tickets do |t|
      t.string :ticket_number, null: false
      t.bigint :account_id
      t.bigint :dealer_id
      t.bigint :admin_user_id
      t.string :user_type, null: false
      t.string :subject, null: false
      t.text :description, null: false
      t.string :category, null: false
      t.string :priority, default: "medium"
      t.string :status, default: "open"
      t.bigint :assigned_to_id
      t.datetime :resolved_at
      t.string :resolution_summary
      t.integer :messages_count, default: 0
      t.timestamps

      t.index :account_id
      t.index :admin_user_id
      t.index :assigned_to_id
      t.index :category
      t.index :dealer_id
      t.index :priority
      t.index :status
      t.index :ticket_number
      t.index :user_type
    end
  end
end
