class AddTokenVersionToActors < ActiveRecord::Migration[8.0]
  def change
    add_column :accounts, :token_version, :integer, default: 0, null: false
    add_column :dealers, :token_version, :integer, default: 0, null: false
    add_column :admin_users, :token_version, :integer, default: 0, null: false
  end
end
