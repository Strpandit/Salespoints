class CreateDealerOffers < ActiveRecord::Migration[8.0]
  def change
    create_table :dealer_offers do |t|
      t.bigint :dealer_id, null: false
      t.bigint :dealer_product_id, null: false
      t.bigint :product_id, null: false
      t.bigint :product_variant_id, null: false

      t.string :offer_name, null: false
      t.string :scheme_category, null: false
      t.string :product_condition, null: false
      t.string :seller_code
      t.text :special_terms

      # Descriptors (autofilled from catalog, editable to describe the specific unit)
      t.string :brand_name
      t.string :device_model
      t.string :variant_name
      t.string :ram_storage
      t.string :colour
      t.boolean :imei_required, default: false, null: false
      t.string :warranty
      t.text :included_accessories
      t.boolean :return_replacement, default: false, null: false

      # Pricing
      t.decimal :mrp, precision: 12, scale: 2, default: "0.0", null: false
      t.decimal :seller_price, precision: 12, scale: 2, default: "0.0", null: false
      t.decimal :offer_price, precision: 12, scale: 2, default: "0.0", null: false
      t.decimal :tax_rate, precision: 5, scale: 2

      # Stock / validity
      t.integer :available_quantity, default: 0, null: false
      t.integer :sold_quantity, default: 0, null: false
      t.datetime :offer_starts_at
      t.datetime :offer_ends_at

      # Delivery targeting
      t.string :pincodes, array: true, default: []

      # Workflow
      t.string :approve_status, default: "pending", null: false
      t.boolean :is_active, default: true, null: false
      t.text :rejection_reason
      t.datetime :reviewed_at
      t.bigint :reviewed_by_admin_id

      t.timestamps

      t.index :dealer_id
      t.index :dealer_product_id
      t.index :product_id
      t.index :product_variant_id
      t.index :reviewed_by_admin_id
      t.index :scheme_category
      t.index [ :approve_status, :is_active ]
      t.index :pincodes, using: :gin
    end
  end
end
