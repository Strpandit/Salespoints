super_admin_email    = ENV.fetch('SUPER_ADMIN_EMAIL', 'salespointecom@gmail.com')
super_admin_password = ENV.fetch('SUPER_ADMIN_PASSWORD', 'Salespoints@2026')

super_admin = AdminUser.find_or_initialize_by(email: super_admin_email) do |user|
  user.password = super_admin_password
  user.password_confirmation = super_admin_password
  user.first_name = 'Sales'
  user.last_name = 'Points'
  user.is_super_admin = true
  user.status = 'active'
end
super_admin.save!
super_admin.update!(
  approval_status: 'approved',
  approved_at: Time.current,
  approved_by_id: super_admin.id
)
role = Role.find_or_create_by!(name: 'Super Admin') do |role|
  role.module_access = Role::ALLOWED_MODULES
  role.is_active = true
  role.created_by_id = super_admin.id
end
AdminRole.find_or_create_by!(admin_user_id: super_admin.id, role_id: role.id)