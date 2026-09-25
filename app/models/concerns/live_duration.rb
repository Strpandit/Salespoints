module LiveDuration
  extend ActiveSupport::Concern

  OPTIONS = [ 7, 15, 25, 30 ].freeze
  DEFAULT = 7
  MAX = OPTIONS.max

  included do
    validate :live_days_allowed
  end

  def self.options_payload
    OPTIONS.map { |d| { value: d, label: "#{d} Days" } }
  end

  def live_days_allowed
    return if OPTIONS.include?(live_days.to_i)

    errors.add(:base, "Live duration must be one of #{OPTIONS.join(', ')} days")
  end

  def live_duration
    (live_days.presence || DEFAULT).to_i.days
  end

  def live_duration_label
    "#{(live_days.presence || DEFAULT).to_i} Days"
  end
end
