class CatFilterSerializer < ApplicationSerializer
  attributes :id, :name, :data_type, :unit, :options, :is_mandatory, :is_filterable, :display_order, :category_id

  belongs_to :category
end

