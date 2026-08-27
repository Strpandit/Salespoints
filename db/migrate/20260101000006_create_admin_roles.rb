class CreateAdminRoles < ActiveRecord::Migration[8.0]
  def change
    create_table :admin_roles do |t|
      t.integer :admin_user_id, null: false
      t.integer :role_id, null: false
      t.timestamps

      t.index [:admin_user_id, :role_id], unique: true
      t.index :admin_user_id
      t.index :role_id

      t.foreign_key :admin_users
      t.foreign_key :roles
    end
  end
end
