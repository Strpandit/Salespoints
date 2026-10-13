class AddPerformanceIndexes < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :orders, [:seller_dealer_id, :created_at],
              name: "idx_orders_on_seller_dealer_and_created_at",
              algorithm: :concurrently, if_not_exists: true
    add_index :orders, :created_at,
              name: "idx_orders_on_created_at",
              algorithm: :concurrently, if_not_exists: true
    add_index :b2b_orders, :created_at,
              name: "idx_b2b_orders_on_created_at",
              algorithm: :concurrently, if_not_exists: true
    add_index :b2b_orders, :payment_session_id,
              name: "idx_b2b_orders_on_payment_session_id",
              algorithm: :concurrently, if_not_exists: true
    add_index :notifications, [:receiver_type, :receiver_id, :created_at],
              name: "idx_notifications_on_receiver_and_created_at",
              algorithm: :concurrently, if_not_exists: true
  end
end
