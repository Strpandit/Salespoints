class CreateB2bOrderItems < ActiveRecord::Migration[8.0]
  def change
    create_table :b2b_order_items do |t|
      t.bigint :b2b_order_id, null: false
      t.bigint :dealer_product_id
      t.bigint :product_variant_id
      t.integer :quantity, default: 1, null: false
      t.decimal :unit_price, precision: 12, scale: 2, default: "0.0", null: false
      t.decimal :total_price, precision: 12, scale: 2, default: "0.0", null: false
      t.string :status, default: "open", null: false
      t.datetime :responded_at
      t.integer :wholesaler_post_id
      t.bigint :product_variant_color_id
      t.string :ad_hoc_color
      t.timestamps

      t.index :b2b_order_id
      t.index :dealer_product_id
      t.index :product_variant_color_id
      t.index :product_variant_id
      t.index :status
      t.index :wholesaler_post_id

      t.foreign_key :b2b_orders
      t.foreign_key :dealer_products
      t.foreign_key :product_variants
      t.foreign_key :product_variant_colors
    end
  end
end
