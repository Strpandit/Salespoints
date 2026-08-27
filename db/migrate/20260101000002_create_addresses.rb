class CreateAddresses < ActiveRecord::Migration[8.0]
  def change
    create_table :addresses do |t|
      t.integer :account_id
      t.string :name
      t.string :address_line1, null: false
      t.string :address_line2
      t.string :city, null: false
      t.string :state, null: false
      t.string :country, default: "India", null: false
      t.string :postal_code, null: false
      t.string :phone
      t.integer :address_type, default: 0
      t.boolean :is_default, default: false
      t.decimal :latitude, precision: 10, scale: 6
      t.decimal :longitude, precision: 10, scale: 6
      t.bigint :dealer_id
      t.timestamps

      t.index :account_id
      t.index :dealer_id

      t.foreign_key :accounts
      t.foreign_key :dealers
    end
  end
end
