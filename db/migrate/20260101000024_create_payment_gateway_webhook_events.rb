class CreatePaymentGatewayWebhookEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :payment_gateway_webhook_events do |t|
      t.string :provider, null: false
      t.string :event_type
      t.string :event_id, null: false
      t.string :payload_digest, null: false
      t.string :status, default: "received", null: false
      t.integer :response_code
      t.datetime :received_at, null: false
      t.datetime :processed_at
      t.jsonb :headers, default: {}, null: false
      t.jsonb :payload, default: {}, null: false
      t.text :error_message
      t.integer :attempts, default: 0, null: false
      t.timestamps

      t.index [:provider, :event_id], name: "idx_pg_webhook_events_unique", unique: true
      t.index :received_at
      t.index :status
    end
  end
end
