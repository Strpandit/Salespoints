class CreateHomeBanners < ActiveRecord::Migration[8.0]
  def change
    create_table :hero_slides do |t|
      t.string :badge
      t.string :title
      t.string :highlight, null: false
      t.text :subtitle
      t.string :discount_text
      t.string :cta_label, default: "Explore Now", null: false
      t.string :link_url
      t.string :secondary_cta_label, default: "View Deals"
      t.string :secondary_link_url, default: "/shop"
      t.string :theme, default: "blue", null: false
      t.integer :position, default: 0, null: false
      t.boolean :is_active, default: true, null: false
      t.datetime :starts_at
      t.datetime :ends_at
      t.timestamps
    end
    add_index :hero_slides, [ :is_active, :position ]

    create_table :flash_sales do |t|
      t.string :title, null: false
      t.string :badge_text, default: "LIMITED TIME DEALS"
      t.text :subtitle
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.boolean :is_active, default: true, null: false
      t.boolean :show_countdown, default: true, null: false
      t.integer :position, default: 0, null: false
      t.timestamps
    end
    add_index :flash_sales, [ :is_active, :starts_at, :ends_at ]

    create_table :flash_sale_items do |t|
      t.references :flash_sale, null: false, foreign_key: { on_delete: :cascade }
      t.string :item_type, null: false
      t.bigint :item_id, null: false
      t.string :label
      t.integer :position, default: 0, null: false
      t.timestamps
    end
    add_index :flash_sale_items, [ :flash_sale_id, :item_type, :item_id ], unique: true, name: "index_flash_sale_items_uniqueness"
    add_index :flash_sale_items, [ :item_type, :item_id ]
  end
end
