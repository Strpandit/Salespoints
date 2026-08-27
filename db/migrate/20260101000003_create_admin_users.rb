class CreateAdminUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :admin_users do |t|
      t.string :first_name
      t.string :last_name
      t.string :email
      t.string :phone
      t.string :country_code, default: "+91"
      t.string :status, default: "active"
      t.string :password_digest
      t.string :otp_pin
      t.datetime :otp_sent_at
      t.string :reset_password_token
      t.datetime :reset_password_sent_at
      t.datetime :deleted_at
      t.datetime :last_login_at
      t.boolean :is_super_admin, default: false
      t.string :alternate_phone
      t.text :address
      t.string :aadhar_number
      t.string :pan_number
      t.string :bank_name
      t.string :bank_account_number
      t.string :ifsc_code
      t.string :account_holder_name
      t.string :tenth_school_name
      t.string :tenth_board
      t.string :tenth_passing_year
      t.string :tenth_percentage
      t.string :twelfth_school_name
      t.string :twelfth_board
      t.string :twelfth_passing_year
      t.string :twelfth_percentage
      t.string :approval_status, default: "pending", null: false
      t.datetime :approved_at
      t.bigint :approved_by_id
      t.decimal :salary, precision: 15, scale: 2
      t.bigint :deleted_by_id
      t.date :joining_date
      t.string :pincodes, array: true, default: []
      t.string :signup_token
      t.datetime :signup_token_sent_at
      t.timestamps

      t.index :approval_status
      t.index :approved_by_id
      t.index :deleted_by_id
      t.index :email, unique: true, where: "(deleted_at IS NULL)"
      t.index :is_super_admin
      t.index :phone, unique: true, where: "(deleted_at IS NULL)"
      t.index :pincodes, using: :gin
      t.index :signup_token, unique: true

      t.foreign_key :admin_users, column: :approved_by_id
      t.foreign_key :admin_users, column: :deleted_by_id
    end
  end
end
