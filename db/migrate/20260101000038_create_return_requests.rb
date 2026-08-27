class CreateReturnRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :return_requests do |t|
      t.string :requester_type, null: false
      t.bigint :requester_id, null: false
      t.string :request_type, null: false
      t.string :status, default: "requested", null: false
      t.text :reason
      t.text :details
      t.decimal :refund_amount, precision: 12, scale: 2, default: "0.0", null: false
      t.decimal :seller_adjustment_amount, precision: 12, scale: 2, default: "0.0", null: false
      t.text :resolution_notes
      t.datetime :approved_at
      t.datetime :received_at
      t.datetime :completed_at
      t.datetime :rejected_at
      t.datetime :cancelled_at
      t.datetime :shipped_at
      t.string :requestable_type, null: false
      t.bigint :requestable_id, null: false
      t.string :replacement_mode, default: "full", null: false
      t.integer :defective_quantity, default: 1, null: false
      t.json :defective_serial_numbers, default: []
      t.json :replacement_serial_numbers, default: []
      t.timestamps

      t.index :replacement_mode
      t.index :request_type
      t.index [:requestable_type, :requestable_id]
      t.index [:requester_type, :requester_id]
      t.index :status
    end
  end
end
