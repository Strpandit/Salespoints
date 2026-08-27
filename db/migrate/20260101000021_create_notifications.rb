class CreateNotifications < ActiveRecord::Migration[8.0]
  def change
    create_table :notifications do |t|
      t.string :receiver_type, null: false
      t.bigint :receiver_id, null: false
      t.string :actor_type
      t.bigint :actor_id
      t.string :notifiable_type
      t.bigint :notifiable_id
      t.string :notification_type, null: false
      t.string :title, null: false
      t.text :body
      t.jsonb :payload, default: {}, null: false
      t.datetime :read_at
      t.datetime :sent_at
      t.timestamps

      t.index [:notifiable_type, :notifiable_id]
      t.index :read_at
      t.index [:receiver_type, :receiver_id]
    end
  end
end
