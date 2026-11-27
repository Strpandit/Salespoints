class AddCreatedByToAdminUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :admin_users, :created_by_id, :bigint unless column_exists?(:admin_users, :created_by_id)
    add_index :admin_users, :created_by_id unless index_exists?(:admin_users, :created_by_id)

    reversible do |dir|
      dir.up do
        super_admin = AdminUser.find_by(is_super_admin: true) ||
                      AdminUser.joins(:roles).find_by(roles: { name: 'Super Admin' }) ||
                      AdminUser.find_by(email: ENV.fetch('SUPER_ADMIN_EMAIL', 'salespointecom@gmail.com'))

        if super_admin
          AdminUser.where(created_by_id: nil).where.not(id: super_admin.id).update_all(created_by_id: super_admin.id)
        end
      end
    end
  end
end
