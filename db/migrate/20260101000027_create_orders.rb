class CreateOrders < ActiveRecord::Migration[8.0]
  def change
    create_table :orders do |t|
      t.string :order_number, null: false
      t.string :buyer_type, null: false
      t.bigint :buyer_id, null: false
      t.bigint :seller_dealer_id
      t.string :status, default: "pending", null: false
      t.decimal :subtotal_amount, precision: 12, scale: 2, default: "0.0", null: false
      t.decimal :tax_amount, precision: 12, scale: 2, default: "0.0", null: false
      t.decimal :discount_amount, precision: 12, scale: 2, default: "0.0", null: false
      t.decimal :total_amount, precision: 12, scale: 2, default: "0.0", null: false
      t.string :coupon_code
      t.string :payment_method, default: "cod", null: false
      t.string :payment_status, default: "pending", null: false
      t.datetime :placed_at
      t.jsonb :billing_address, default: {}, null: false
      t.jsonb :shipping_address, default: {}, null: false
      t.string :payment_gateway
      t.string :gateway_order_reference
      t.string :payment_session_id
      t.string :payment_reference
      t.jsonb :payment_gateway_payload, default: {}, null: false
      t.text :status_note
      t.datetime :payment_confirmed_at
      t.datetime :cancelled_at
      t.datetime :delivered_at
      t.datetime :shipped_at
      t.datetime :processing_at
      t.decimal :commission_rate, precision: 5, scale: 2, default: "10.0", null: false
      t.decimal :commission_amount, precision: 12, scale: 2, default: "0.0", null: false
      t.decimal :marketplace_fee_amount, precision: 12, scale: 2, default: "0.0", null: false
      t.decimal :seller_settlement_amount, precision: 12, scale: 2, default: "0.0", null: false
      t.string :settlement_status, default: "on_hold", null: false
      t.datetime :settlement_due_at
      t.datetime :settled_at
      t.datetime :hold_released_at
      t.string :refund_status, default: "none", null: false
      t.decimal :refund_amount, precision: 12, scale: 2, default: "0.0", null: false
      t.datetime :refunded_at
      t.text :refund_reason
      t.datetime :return_window_closes_at
      t.datetime :expires_at
      t.datetime :accepted_at
      t.string :invoice_number
      t.timestamps

      t.index [:buyer_type, :buyer_id]
      t.index :expires_at
      t.index :gateway_order_reference
      t.index :invoice_number, unique: true
      t.index :order_number, unique: true
      t.index :payment_reference
      t.index :refund_status
      t.index :settlement_due_at
      t.index :settlement_status
      t.index :status
    end
  end
end
