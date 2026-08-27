class CreateReviews < ActiveRecord::Migration[8.0]
  def change
    create_table :reviews do |t|
      t.integer :account_id, null: false
      t.integer :dealer_product_id
      t.string :title
      t.text :comment
      t.integer :rating
      t.boolean :verified
      t.bigint :product_id
      t.timestamps

      t.index :account_id
      t.index :dealer_product_id
      t.index :product_id
    end
  end
end
