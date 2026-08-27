class CreateB2bOrders < ActiveRecord::Migration[8.0]
  def change
    create_table :b2b_orders do |t|
      t.bigint :buyer_dealer_id, null: false
      t.bigint :seller_dealer_id
      t.string :status, default: "pending", null: false
      t.decimal :subtotal_amount, precision: 12, scale: 2, default: "0.0", null: false
      t.decimal :tax_amount, precision: 12, scale: 2, default: "0.0", null: false
      t.decimal :discount_amount, precision: 12, scale: 2, default: "0.0", null: false
      t.decimal :total_amount, precision: 12, scale: 2, default: "0.0", null: false
      t.string :coupon_code
      t.integer :requested_radius_km, default: 5, null: false
      t.decimal :latitude, precision: 10, scale: 6
      t.decimal :longitude, precision: 10, scale: 6
      t.datetime :accepted_at
      t.datetime :cancelled_at
      t.datetime :expires_at
      t.string :payment_method, default: "cod", null: false
      t.string :payment_status, default: "pending", null: false
      t.bigint :buyer_payment_attempt_id
      t.datetime :last_rebroadcast_at
      t.string :source_type
      t.integer :source_id
      t.boolean :is_direct_buy, default: false
      t.string :request_status, default: "pending_request"
      t.datetime :requested_at
      t.datetime :payment_link_sent_at
      t.datetime :rejected_at
      t.datetime :expired_at
      t.datetime :payment_confirmed_at
      t.datetime :confirmed_at
      t.string :payment_token
      t.string :reference_number, default: ""
      t.integer :current_broadcast_radius, default: 5
      t.integer :broadcast_attempts, default: 0
      t.datetime :shipped_at
      t.datetime :delivered_at
      t.text :status_note
      t.jsonb :billing_address, default: {}, null: false
      t.jsonb :shipping_address, default: {}, null: false
      t.string :payment_gateway
      t.string :payment_session_id
      t.string :payment_reference
      t.string :gateway_order_reference
      t.jsonb :payment_gateway_payload, default: {}
      t.string :invoice_number
      t.string :tracking_id
      t.timestamps

      t.index :broadcast_attempts
      t.index :buyer_dealer_id
      t.index :buyer_payment_attempt_id
      t.index :current_broadcast_radius
      t.index :gateway_order_reference, name: "idx_b2b_orders_on_gateway_order_reference"
      t.index :invoice_number, unique: true
      t.index :is_direct_buy
      t.index :payment_method
      t.index :payment_reference, name: "idx_b2b_orders_on_payment_reference"
      t.index :payment_status
      t.index :payment_token, unique: true
      t.index :reference_number, unique: true
      t.index [:request_status, :expires_at]
      t.index :request_status
      t.index :seller_dealer_id
      t.index [:source_type, :source_id]
      t.index :status
      t.index :tracking_id, unique: true

      t.foreign_key :dealers, column: :buyer_dealer_id
      t.foreign_key :dealers, column: :seller_dealer_id
      t.foreign_key :payment_attempts, column: :buyer_payment_attempt_id
    end
  end
end
