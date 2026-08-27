class CreateDealerProducts < ActiveRecord::Migration[8.0]
  def change
    create_table :dealer_products do |t|
      t.integer :dealer_id, null: false
      t.integer :product_id, null: false
      t.integer :product_variant_id, null: false
      t.boolean :is_active, default: true
      t.integer :approve_status, default: 0
      t.boolean :sell_in_b2b, default: true, null: false
      t.boolean :sell_in_b2c, default: true, null: false
      t.integer :stock_quantity, default: 0
      t.jsonb :color_stocks, default: {}, null: false
      t.timestamps

      t.index :approve_status
      t.index :dealer_id
      t.index :product_id
      t.index :product_variant_id
    end
  end
end
