class CreateOrderItems < ActiveRecord::Migration[8.0]
  def change
    create_table :order_items do |t|
      t.bigint :order_id, null: false
      t.bigint :product_variant_id, null: false
      t.integer :quantity, default: 1, null: false
      t.decimal :unit_price, precision: 12, scale: 2, default: "0.0", null: false
      t.decimal :total_price, precision: 12, scale: 2, default: "0.0", null: false
      t.integer :dealer_product_id
      t.bigint :product_variant_color_id
      t.string :ad_hoc_color
      t.timestamps

      t.index :dealer_product_id
      t.index :order_id
      t.index :product_variant_color_id
      t.index :product_variant_id
    end
  end
end
