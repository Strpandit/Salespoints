class CreateTicketMessages < ActiveRecord::Migration[8.0]
  def change
    create_table :ticket_messages do |t|
      t.bigint :support_ticket_id, null: false
      t.bigint :account_id
      t.bigint :admin_user_id
      t.string :sender_type, null: false
      t.text :message, null: false
      t.integer :attachments_count, default: 0
      t.boolean :is_internal, default: false
      t.bigint :dealer_id
      t.timestamps

      t.index :account_id
      t.index :admin_user_id
      t.index :created_at
      t.index :dealer_id
      t.index :support_ticket_id
    end
  end
end
