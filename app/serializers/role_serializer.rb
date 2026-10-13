class RoleSerializer < ApplicationSerializer
  attributes :name, :is_active, :module_access, :module_permissions, :created_by

  def module_permissions
    object.module_permissions || {}
  end

  # Minimal creator reference: the full AdminUserSerializer would expose the creator's KYC / bank / salary
  # data to anyone who can read roles.
  def created_by
    creator = object.created_by
    return nil unless creator

    { id: creator.id, full_name: creator.full_name, email: creator.email }
  end
end
