class CreatePaymentAttempts < ActiveRecord::Migration[8.0]
  def change
    create_table :payment_attempts do |t|
      t.string :attempt_number, null: false
      t.string :buyer_type, null: false
      t.bigint :buyer_id, null: false
      t.string :status, default: "pending", null: false
      t.decimal :amount, precision: 12, scale: 2, default: "0.0", null: false
      t.string :currency, default: "INR", null: false
      t.string :coupon_code
      t.jsonb :billing_address, default: {}, null: false
      t.jsonb :shipping_address, default: {}, null: false
      t.jsonb :cart_snapshot, default: {}, null: false
      t.string :payment_gateway, default: "cashfree", null: false
      t.string :gateway_order_reference
      t.string :payment_session_id
      t.string :payment_reference
      t.jsonb :payment_gateway_payload, default: {}, null: false
      t.text :failure_reason
      t.datetime :paid_at
      t.datetime :cancelled_at
      t.datetime :failed_at
      t.datetime :processed_at
      t.jsonb :result_payload, default: {}, null: false
      t.timestamps

      t.index :attempt_number, unique: true
      t.index [:buyer_type, :buyer_id]
      t.index :gateway_order_reference
      t.index :payment_reference
      t.index :status
    end
  end
end
