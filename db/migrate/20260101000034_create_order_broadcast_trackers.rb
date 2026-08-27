class CreateOrderBroadcastTrackers < ActiveRecord::Migration[8.0]
  def change
    create_table :order_broadcast_trackers do |t|
      t.bigint :order_id, null: false
      t.bigint :dealer_id, null: false
      t.integer :broadcast_radius_km, default: 5
      t.integer :attempt_count, default: 1
      t.string :status, default: "pending"
      t.datetime :last_broadcast_at
      t.datetime :expires_at
      t.timestamps

      t.index :dealer_id
      t.index [:order_id, :dealer_id], name: "idx_order_broadcast_trackers_order_dealer", unique: true
      t.index [:order_id, :status], name: "idx_order_broadcast_trackers_order_status"
      t.index :order_id
    end
  end
end
