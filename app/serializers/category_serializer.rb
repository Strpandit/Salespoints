class CategorySerializer < ApplicationSerializer
  attributes :id, :name, :slug, :is_active, :cat_icon

  attributes :brands do |category|
    category.brands.map do |brand|
      {
        id: brand.id,
        name: brand.name,
        slug: brand.slug
      }
    end
  end

  has_many :cat_filters

  def cat_icon
    return nil unless object.cat_icon.attached?

    file_payload(object.cat_icon)
  end

  private

  def file_payload(file)
    host = options[:base_url] ||
           Rails.application.config.active_storage.default_url_options&.dig(:host)
    BlobUrlHelper.attachment_payload(file, host: host)
  end
end
