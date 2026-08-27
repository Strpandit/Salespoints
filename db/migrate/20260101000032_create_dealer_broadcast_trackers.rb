class CreateDealerBroadcastTrackers < ActiveRecord::Migration[8.0]
  def change
    create_table :dealer_broadcast_trackers do |t|
      t.integer :broadcast_radius_km, default: 5
      t.integer :attempt_count, default: 1
      t.datetime :last_broadcast_at
      t.string :status, default: "pending"
      t.bigint :dealer_id, null: false
      t.bigint :b2b_order_id, null: false
      t.timestamps

      t.index [:b2b_order_id, :dealer_id], name: "idx_broadcast_trackers_order_dealer", unique: true
      t.index [:b2b_order_id, :status], name: "idx_broadcast_trackers_order_status"
      t.index :b2b_order_id
      t.index :dealer_id

      t.foreign_key :dealers
      t.foreign_key :b2b_orders
    end
  end
end
