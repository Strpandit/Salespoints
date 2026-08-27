class CreateCoupons < ActiveRecord::Migration[8.0]
  def change
    create_table :coupons do |t|
      t.string :code, null: false
      t.string :title
      t.text :description
      t.bigint :created_by_dealer_id
      t.string :audience, default: "customer", null: false
      t.string :discount_type, default: "percentage", null: false
      t.decimal :discount_value, precision: 10, scale: 2, default: "0.0", null: false
      t.decimal :max_discount, precision: 10, scale: 2
      t.decimal :min_cart_amount, precision: 10, scale: 2, default: "0.0", null: false
      t.integer :max_uses
      t.integer :used_count, default: 0, null: false
      t.integer :per_user_limit, default: 1, null: false
      t.datetime :starts_at
      t.datetime :expires_at
      t.boolean :is_active, default: true, null: false
      t.timestamps

      t.index :audience
      t.index :code, unique: true
      t.index :created_by_dealer_id

      t.foreign_key :dealers, column: :created_by_dealer_id
    end
  end
end
