class CreateContactFormSubmissions < ActiveRecord::Migration[8.0]
  def change
    create_table :contact_form_submissions do |t|
      t.string :name, null: false
      t.string :email, null: false
      t.string :phone
      t.string :subject, null: false
      t.text :message, null: false
      t.string :status, default: "received"
      t.text :admin_response
      t.bigint :admin_user_id
      t.datetime :responded_at
      t.timestamps

      t.index :admin_user_id
      t.index :email
      t.index :status
    end
  end
end
