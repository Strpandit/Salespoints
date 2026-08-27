class CreateDealerPayouts < ActiveRecord::Migration[8.0]
  def change
    create_table :dealer_payouts do |t|
      t.bigint :dealer_id, null: false
      t.string :request_number, null: false
      t.decimal :amount, precision: 12, scale: 2, default: "0.0", null: false
      t.string :status, default: "pending", null: false
      t.string :bank_name
      t.string :bank_account_number
      t.string :ifsc_code
      t.string :account_holder_name
      t.string :payment_reference
      t.string :payment_mode
      t.text :admin_note
      t.datetime :approved_at
      t.datetime :processing_at
      t.datetime :paid_at
      t.datetime :rejected_at
      t.datetime :cancelled_at
      t.bigint :approved_by_admin_id
      t.bigint :processed_by_admin_id
      t.jsonb :metadata, default: {}, null: false
      t.string :requestable_type
      t.bigint :requestable_id
      t.string :invoice_number
      t.timestamps

      t.index :approved_by_admin_id
      t.index :dealer_id
      t.index :processed_by_admin_id
      t.index :request_number, unique: true
      t.index [:requestable_type, :requestable_id]
      t.index :status

      t.foreign_key :dealers
      t.foreign_key :admin_users, column: :approved_by_admin_id
      t.foreign_key :admin_users, column: :processed_by_admin_id
    end
  end
end
