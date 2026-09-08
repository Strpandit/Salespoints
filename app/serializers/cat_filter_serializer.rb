class CatFilterSerializer < ApplicationSerializer
  attributes :id, :name, :data_type, :unit, :is_mandatory, :is_filterable, :display_order, :category_id, :options, :category

  def options
    opts = object.options
    if opts.is_a?(String)
      begin
        parsed = JSON.parse(opts)
        parsed.is_a?(Array) ? parsed : opts.split(",").map(&:strip).reject(&:blank?)
      rescue JSON::ParserError
        opts.split(",").map(&:strip).reject(&:blank?)
      end
    elsif opts.is_a?(Array)
      opts
    else
      []
    end
  end

  def category
    return nil unless object.category

    {
      id: object.category.id,
      name: object.category.name,
      slug: object.category.slug
    }
  end
end

