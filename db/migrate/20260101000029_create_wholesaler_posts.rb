class CreateWholesalerPosts < ActiveRecord::Migration[8.0]
  def change
    create_table :wholesaler_posts do |t|
      t.bigint :dealer_id, null: false
      t.bigint :dealer_product_id
      t.string :title
      t.text :body
      t.decimal :price, precision: 12, scale: 2
      t.string :modal_no
      t.decimal :rating, precision: 3, scale: 2, default: "0.0", null: false
      t.integer :rating_count, default: 0, null: false
      t.string :approve_status, default: "pending", null: false
      t.datetime :reviewed_at
      t.text :rejection_reason
      t.bigint :reviewed_by_admin_id
      t.string :pincodes, array: true, default: []
      t.datetime :reuploaded_at
      t.string :hsn_code
      t.string :ad_hoc_color
      t.integer :stock_quantity, default: 0
      t.string :mf_year
      t.timestamps

      t.index :approve_status
      t.index :dealer_id
      t.index :dealer_product_id
      t.index :pincodes, using: :gin
      t.index :reviewed_by_admin_id
    end
  end
end
