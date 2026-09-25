# Shared guard for the admin Home Banners screens (hero slides + flash sales).
# Super admins only — deliberately not a Role module, so it can't be delegated.
module HomeBannerAdmin
  extend ActiveSupport::Concern

  included do
    before_action :require_super_admin!
  end

  private

  def require_super_admin!
    return if current_admin&.super_admin?

    render json: { error: "Only super admins can manage home banners" }, status: :forbidden
  end

  def banner_payload
    @banner_payload ||= Storefront::BannerPayload.new(base_url: request.base_url)
  end

  # Multipart/JSON forms send "" for cleared optional values.
  def blank_to_nil!(permitted, *keys)
    keys.each { |k| permitted[k] = nil if permitted.key?(k) && permitted[k].blank? }
    permitted
  end
end
