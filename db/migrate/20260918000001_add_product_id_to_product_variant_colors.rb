class AddProductIdToProductVariantColors < ActiveRecord::Migration[8.0]
  def change
    add_reference :product_variant_colors, :product, foreign_key: true, index: true
    change_column_null :product_variant_colors, :product_variant_id, true

    reversible do |dir|
      dir.up do
        ProductVariantColor.reset_column_information
        ProductVariantColor.find_each do |color|
          if color.product_variant_id.present?
            variant = ProductVariant.find_by(id: color.product_variant_id)
            color.update_column(:product_id, variant.product_id) if variant
          end
        end
      end
    end
  end
end
