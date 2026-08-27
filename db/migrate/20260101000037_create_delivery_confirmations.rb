class CreateDeliveryConfirmations < ActiveRecord::Migration[8.0]
  def change
    create_table :delivery_confirmations do |t|
      t.string :token, null: false
      t.string :deliverable_type, null: false
      t.bigint :deliverable_id, null: false
      t.bigint :seller_dealer_id
      t.string :buyer_type, null: false
      t.bigint :buyer_id, null: false
      t.string :status, default: "pending_form", null: false
      t.jsonb :declarations, default: {}, null: false
      t.text :notes
      t.string :seller_phone
      t.string :buyer_phone
      t.string :seller_otp
      t.datetime :seller_otp_sent_at
      t.datetime :seller_otp_verified_at
      t.string :buyer_otp
      t.datetime :buyer_otp_sent_at
      t.datetime :buyer_otp_verified_at
      t.datetime :submitted_at
      t.datetime :completed_at
      t.string :serial_numbers, array: true, default: []
      t.string :context, default: "original", null: false
      t.bigint :return_request_id
      t.timestamps

      t.index [:buyer_type, :buyer_id]
      t.index :context
      t.index [:deliverable_type, :deliverable_id, :context], name: "idx_delivery_confirmations_on_deliverable_context", unique: true
      t.index :return_request_id, where: "(return_request_id IS NOT NULL)"
      t.index :seller_dealer_id
      t.index :status
      t.index :token, unique: true
    end
  end
end
