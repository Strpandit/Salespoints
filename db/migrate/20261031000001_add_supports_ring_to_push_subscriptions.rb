class AddSupportsRingToPushSubscriptions < ActiveRecord::Migration[8.0]
  def change
    add_column :push_subscriptions, :supports_ring, :boolean, default: false, null: false
  end
end
