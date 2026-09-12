module CrossActorUniqueness
  extend ActiveSupport::Concern

  ACTOR_LABELS = {
    "Account" => "Customer",
    "Dealer" => "Dealer",
    "AdminUser" => "Admin"
  }.freeze

  ACTOR_MODEL_NAMES = ACTOR_LABELS.keys.freeze

  class_methods do
    def validates_uniqueness_across_actors(*fields)
      class_attribute :cross_actor_unique_fields, instance_writer: false unless respond_to?(:cross_actor_unique_fields)
      self.cross_actor_unique_fields = fields.map(&:to_sym)
      validate :check_uniqueness_across_actors
    end
  end

  private

  def check_uniqueness_across_actors
    Array(self.class.cross_actor_unique_fields).each do |field|
      value = public_send(field)
      next if value.blank?

      ACTOR_MODEL_NAMES.each do |model_name|
        next if model_name == self.class.name

        model = model_name.constantize
        next unless model.column_names.include?(field.to_s)

        scope = field == :email ? model.where("LOWER(email) = ?", value.to_s.downcase) : model.where(field => value)
        scope = scope.where(deleted_at: nil) if model.column_names.include?("deleted_at")

        if scope.exists?
          errors.add(field, "is already registered. Please use a different #{field}.")
          break
        end
      end
    end
  end
end
