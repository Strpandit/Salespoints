class JsonWebToken
  SECRET = Rails.application.credentials.jwt_secret || Rails.application.secret_key_base
  ALGORITHM = 'HS256'
  VERSION_CLAIM = :tv

  def self.encode(payload, exp = 2.years.from_now)
    JWT.encode(payload.merge(exp: exp.to_i), SECRET, ALGORITHM)
  end

  def self.decode(token)
    JWT.decode(token, SECRET, true, algorithm: ALGORITHM)[0].with_indifferent_access
  end

  # Session token for an Account, Dealer or AdminUser, stamped with its current token_version
  # so `revoke_tokens!` on the record invalidates it.
  def self.issue_for(user)
    encode(user_id: user.id, user_type: user.class.name, VERSION_CLAIM => token_version_of(user))
  end

  # Tokens minted before versioning existed carry no claim and count as version 0.
  def self.current_version?(payload, user)
    payload[VERSION_CLAIM].to_i == token_version_of(user)
  end

  def self.token_version_of(user)
    user.has_attribute?(:token_version) ? user.token_version.to_i : 0
  end
end
