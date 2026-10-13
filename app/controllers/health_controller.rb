class HealthController < ActionController::API
  def db
    ActiveRecord::Base.connection_pool.with_connection { |conn| conn.select_value("SELECT 1") }
    render json: { status: "ok", database: "up", time: Time.current.iso8601 }, status: :ok
  rescue StandardError
    render json: { status: "error", database: "down" }, status: :service_unavailable
  end
end
