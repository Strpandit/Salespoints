class CreatePushSubscriptions < ActiveRecord::Migration[8.0]
  def change
    create_table :push_subscriptions do |t|
      t.string :subscriber_type, null: false
      t.bigint :subscriber_id, null: false
      t.string :token, null: false
      t.string :platform
      t.timestamps

      t.index [:subscriber_type, :subscriber_id]
      t.index :token, unique: true
    end
  end
end
