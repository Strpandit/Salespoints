class CreateRoles < ActiveRecord::Migration[8.0]
  def change
    create_table :roles do |t|
      t.string :name
      t.text :module_access, default: "--- []\n"
      t.boolean :is_active, default: true
      t.integer :created_by_id
      t.text :module_permissions, default: "--- {}\n"
      t.timestamps

      t.index :created_by_id
    end
  end
end
