class CreateDealerLedgerEntries < ActiveRecord::Migration[8.0]
  def change
    create_table :dealer_ledger_entries do |t|
      t.bigint :dealer_id, null: false
      t.bigint :order_id
      t.bigint :return_request_id
      t.string :entry_type, null: false
      t.string :direction, null: false
      t.decimal :amount, precision: 12, scale: 2, default: "0.0", null: false
      t.decimal :balance_after, precision: 14, scale: 2, default: "0.0", null: false
      t.string :reference_code
      t.text :description
      t.jsonb :metadata, default: {}, null: false
      t.timestamps

      t.index :dealer_id
      t.index :entry_type
      t.index :order_id
      t.index :reference_code, unique: true
      t.index :return_request_id
    end
  end
end
