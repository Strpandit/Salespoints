# Invalidates every session token already issued to this record (see JsonWebToken.issue_for).
module TokenRevocable
  extend ActiveSupport::Concern

  def revoke_tokens!
    return unless has_attribute?(:token_version)

    # Atomic, skips validations/callbacks so it is safe on legacy rows that fail newer validations.
    self.class.where(id: id).update_all("token_version = token_version + 1")
    self.token_version = token_version.to_i + 1
    clear_attribute_change(:token_version)
  end
end
