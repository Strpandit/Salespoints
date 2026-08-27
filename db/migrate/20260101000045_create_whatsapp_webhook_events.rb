class CreateWhatsappWebhookEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :whatsapp_webhook_events do |t|
      t.string :provider, default: "meta", null: false
      t.string :event_type, null: false
      t.string :event_key, null: false
      t.string :direction, default: "inbound", null: false
      t.bigint :b2b_order_offer_id
      t.bigint :notification_id
      t.string :message_id
      t.string :conversation_id
      t.string :from_number
      t.string :to_number
      t.string :status
      t.datetime :processed_at
      t.jsonb :payload, default: {}, null: false
      t.text :error_message
      t.bigint :order_offer_id
      t.timestamps

      t.index :b2b_order_offer_id
      t.index :event_key, unique: true
      t.index :event_type
      t.index :message_id
      t.index :notification_id
      t.index :order_offer_id
      t.index :status
    end
  end
end
