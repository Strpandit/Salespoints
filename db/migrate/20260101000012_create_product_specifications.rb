class CreateProductSpecifications < ActiveRecord::Migration[8.0]
  def change
    create_table :product_specifications do |t|
      t.integer :product_id, null: false
      t.string :key
      t.string :value
      t.timestamps

      t.index :product_id
    end
  end
end
