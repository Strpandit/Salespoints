class CreateProducts < ActiveRecord::Migration[8.0]
  def change
    create_table :products do |t|
      t.string :name
      t.string :slug
      t.string :sku
      t.text :desc
      t.string :material
      t.string :features, default: "[]"
      t.string :care_instructions, default: "[]"
      t.integer :brand_id
      t.boolean :is_featured, default: false
      t.boolean :is_new, default: false
      t.boolean :is_active, default: true
      t.integer :category_id, null: false
      t.decimal :tax_rate, precision: 5, scale: 2, default: "0.0", null: false
      t.datetime :deleted_at
      t.decimal :price, precision: 15, scale: 2
      t.decimal :selling_price, precision: 15, scale: 2
      t.decimal :dealer_price, precision: 15, scale: 2
      t.decimal :dealer_selling_price, precision: 15, scale: 2
      t.integer :discount_percentage, default: 0
      t.bigint :primary_media_blob_id
      t.string :hsn_code
      t.timestamps

      t.index :brand_id
      t.index :category_id
      t.index :is_featured
      t.index :primary_media_blob_id
      t.index :sku, unique: true, where: "(deleted_at IS NULL)"
      t.index :slug, unique: true, where: "(deleted_at IS NULL)"
    end
  end
end
