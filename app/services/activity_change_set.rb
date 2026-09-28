class ActivityChangeSet
  IGNORED_FIELDS = %w[
    id created_at updated_at password_digest otp_pin otp_sent_at reset_password_token reset_password_sent_at
    signup_token signup_token_sent_at slug encrypted_password
  ].freeze
  MAX_FIELDS = 30
  MAX_VALUE_LENGTH = 200
  HIDDEN = "[HIDDEN]".freeze

  class << self
    # Returns { "price" => { "from" => "800.0", "to" => "750.0" }, ... } or {} when nothing changed.
    def from(record)
      return {} unless record.respond_to?(:saved_changes)

      changes = record.saved_changes.except(*IGNORED_FIELDS)
      return {} if changes.blank?

      changes.first(MAX_FIELDS).each_with_object({}) do |(field, (from, to)), out|
        out[field] =
          if sensitive?(field)
            { "from" => HIDDEN, "to" => HIDDEN }
          else
            { "from" => format_value(from), "to" => format_value(to) }
          end
      end
    end

    # "price, stock quantity" — used inside the one-line description.
    def summary(changes, limit: 4)
      return nil if changes.blank?

      names = changes.keys.map { |k| k.to_s.humanize(capitalize: false) }
      extra = names.size > limit ? " +#{names.size - limit} more" : ""
      names.first(limit).join(", ") + extra
    end

    private

    def sensitive?(field)
      filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
      filter.filter(field.to_s => "x")[field.to_s] != "x"
    end

    def format_value(value)
      case value
      when nil then nil
      when Time, DateTime, ActiveSupport::TimeWithZone then value.in_time_zone.strftime("%d %b %Y, %I:%M %p")
      when Date then value.strftime("%d %b %Y")
      when BigDecimal, Float then value.to_f.round(2).to_s
      when Array then value.map(&:to_s).join(", ").truncate(MAX_VALUE_LENGTH)
      when Hash then value.to_json.truncate(MAX_VALUE_LENGTH)
      else value.to_s.truncate(MAX_VALUE_LENGTH)
      end
    end
  end
end
