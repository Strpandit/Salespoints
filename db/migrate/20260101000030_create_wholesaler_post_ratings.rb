class CreateWholesalerPostRatings < ActiveRecord::Migration[8.0]
  def change
    create_table :wholesaler_post_ratings do |t|
      t.bigint :wholesaler_post_id, null: false
      t.bigint :dealer_id, null: false
      t.decimal :rating, precision: 3, scale: 2, null: false
      t.timestamps

      t.index :dealer_id
      t.index [:wholesaler_post_id, :dealer_id], name: "idx_wholesaler_post_ratings_unique", unique: true
      t.index :wholesaler_post_id
    end
  end
end
