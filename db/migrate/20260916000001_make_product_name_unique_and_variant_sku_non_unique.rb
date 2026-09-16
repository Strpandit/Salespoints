class MakeProductNameUniqueAndVariantSkuNonUnique < ActiveRecord::Migration[8.0]
  def change
    remove_index :product_variants, name: :index_product_variants_on_variant_sku, if_exists: true
    add_index :product_variants, :variant_sku, if_not_exists: true

    add_index :products, :name, unique: true, where: "(deleted_at IS NULL)", if_not_exists: true
  end
end
