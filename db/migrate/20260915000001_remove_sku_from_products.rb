class RemoveSkuFromProducts < ActiveRecord::Migration[7.1]
  def change
    if index_exists?(:products, :sku)
      remove_index :products, :sku
    end

    if column_exists?(:products, :sku)
      remove_column :products, :sku, :string
    end
  end
end
