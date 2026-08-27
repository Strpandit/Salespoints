class CreateB2bOrderOffers < ActiveRecord::Migration[8.0]
  def change
    create_table :b2b_order_offers do |t|
      t.bigint :b2b_order_id, null: false
      t.bigint :dealer_id, null: false
      t.bigint :notification_id
      t.string :status, default: "open", null: false
      t.string :delivery_channel, default: "whatsapp", null: false
      t.jsonb :item_ids, default: [], null: false
      t.jsonb :delivery_payload, default: {}, null: false
      t.string :accept_token, null: false
      t.string :reject_token, null: false
      t.string :recipient_phone
      t.string :whatsapp_message_id
      t.string :whatsapp_status, default: "pending", null: false
      t.datetime :sent_at
      t.datetime :delivered_at
      t.datetime :read_at
      t.datetime :failed_at
      t.datetime :responded_at
      t.datetime :expires_at
      t.integer :rebroadcast_count, default: 0, null: false
      t.text :failure_reason
      t.string :shipped_token
      t.timestamps

      t.index :accept_token, unique: true
      t.index [:b2b_order_id, :dealer_id]
      t.index :b2b_order_id
      t.index :dealer_id
      t.index :notification_id
      t.index :reject_token, unique: true
      t.index :shipped_token, unique: true
      t.index :status
      t.index :whatsapp_status

      t.foreign_key :b2b_orders
      t.foreign_key :dealers
      t.foreign_key :notifications
    end
  end
end
