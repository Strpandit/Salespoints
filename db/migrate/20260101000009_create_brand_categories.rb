class CreateBrandCategories < ActiveRecord::Migration[8.0]
  def change
    create_table :brand_categories do |t|
      t.bigint :brand_id, null: false
      t.bigint :category_id, null: false
      t.timestamps

      t.index [:brand_id, :category_id], unique: true
      t.index :brand_id
      t.index :category_id

      t.foreign_key :brands
      t.foreign_key :categories
    end
  end
end
