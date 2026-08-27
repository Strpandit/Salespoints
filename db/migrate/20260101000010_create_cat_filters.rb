class CreateCatFilters < ActiveRecord::Migration[8.0]
  def change
    create_table :cat_filters do |t|
      t.string :name
      t.string :data_type
      t.boolean :is_filterable, default: true
      t.integer :category_id
      t.timestamps

      t.index :category_id
      t.foreign_key :categories
    end
  end
end
