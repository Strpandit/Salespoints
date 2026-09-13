require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module SalespointsBe
  class Application < Rails::Application
    config.load_defaults 8.0
    config.action_mailer.deliver_later_queue_name = :mailers
    config.active_storage.resolve_model_to_route = :rails_storage_proxy

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])
    config.autoload_paths << Rails.root.join("app/serializers/concerns")
    config.eager_load_paths << Rails.root.join("app/serializers/concerns")

    # Application Timezone (Indian Standard Time - IST)
    config.time_zone = "Kolkata"
    config.active_record.default_timezone = :utc
  end
end
