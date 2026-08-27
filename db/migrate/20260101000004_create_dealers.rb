class CreateDealers < ActiveRecord::Migration[8.0]
  def change
    create_table :dealers do |t|
      t.string :first_name
      t.string :last_name
      t.string :email
      t.string :phone
      t.string :status, default: "pending"
      t.string :password_digest
      t.string :otp_pin
      t.datetime :otp_sent_at
      t.string :reset_password_token
      t.datetime :reset_password_sent_at
      t.datetime :deleted_at
      t.string :gender
      t.string :country_code, default: "+91"
      t.string :dealer_code, null: false
      t.decimal :settlement_balance, precision: 14, scale: 2, default: "0.0", null: false
      t.bigint :deleted_by_id
      t.string :pincode
      t.string :signup_token
      t.datetime :signup_token_sent_at
      t.timestamps

      t.index :dealer_code, unique: true, where: "(deleted_at IS NULL)"
      t.index :deleted_by_id
      t.index :email, unique: true, where: "(deleted_at IS NULL)"
      t.index :phone, unique: true, where: "(deleted_at IS NULL)"
      t.index :pincode
      t.index :signup_token, unique: true

      t.foreign_key :admin_users, column: :deleted_by_id
    end
  end
end
