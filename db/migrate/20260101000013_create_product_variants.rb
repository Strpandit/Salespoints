class CreateProductVariants < ActiveRecord::Migration[8.0]
  def change
    create_table :product_variants do |t|
      t.integer :product_id, null: false
      t.string :variant_sku
      t.decimal :price, precision: 10, scale: 2, null: false
      t.decimal :selling_price, precision: 10, scale: 2
      t.decimal :dealer_price, precision: 10, scale: 2, null: false
      t.decimal :dealer_selling_price, precision: 10, scale: 2
      t.integer :discount_percentage, default: 0
      t.boolean :is_active, default: true
      t.string :variant_attributes, default: "{}"
      t.datetime :deleted_at
      t.bigint :primary_media_blob_id
      t.string :hsn_code
      t.timestamps

      t.index :primary_media_blob_id
      t.index :product_id
      t.index :variant_sku, unique: true, where: "(deleted_at IS NULL)"
    end
  end
end
