class AddSpecFieldsToCatFilters < ActiveRecord::Migration[8.0]
  def change
    add_column :cat_filters, :is_mandatory, :boolean, default: false, null: false
    add_column :cat_filters, :unit, :string
    add_column :cat_filters, :options, :jsonb, default: []
    add_column :cat_filters, :display_order, :integer, default: 0
  end
end
