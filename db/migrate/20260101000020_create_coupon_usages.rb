class CreateCouponUsages < ActiveRecord::Migration[8.0]
  def change
    create_table :coupon_usages do |t|
      t.bigint :coupon_id, null: false
      t.string :user_type, null: false
      t.bigint :user_id, null: false
      t.integer :uses_count, default: 0, null: false
      t.datetime :last_used_at
      t.timestamps

      t.index [:coupon_id, :user_type, :user_id], name: "idx_coupon_usages_unique", unique: true
      t.index :coupon_id

      t.foreign_key :coupons
    end
  end
end
