class CreateDealerProfiles < ActiveRecord::Migration[8.0]
  def change
    create_table :dealer_profiles do |t|
      t.integer :dealer_id, null: false
      t.string :business_name
      t.json :business_type
      t.string :gst_number
      t.string :pan_number
      t.string :aadhar_number
      t.string :bank_name
      t.string :bank_account_number
      t.string :ifsc_code
      t.text :business_address
      t.string :business_contact_number
      t.string :business_email
      t.boolean :is_verified, default: false
      t.json :work_category
      t.string :associated_brands
      t.string :account_holder_name
      t.string :bank_verification_status, default: "unverified", null: false
      t.string :bank_verification_reference
      t.datetime :bank_verified_at
      t.string :verified_bank_name
      t.string :verified_name_at_bank
      t.text :last_bank_verification_error
      t.jsonb :bank_verification_payload, default: {}, null: false
      t.timestamps

      t.index :bank_verification_reference
      t.index :bank_verification_status
      t.index :dealer_id
    end
  end
end
