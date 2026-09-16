class GenerateInvoicePdfJob < ApplicationJob
  queue_as :pdf_reports

  ALLOWED_ORDER_TYPES = %w[Order B2bOrder].freeze

  retry_on StandardError, attempts: 3, wait: :exponentially_longer

  def perform(order_id, order_type = "Order")
    order_type = order_type.to_s
    unless ALLOWED_ORDER_TYPES.include?(order_type)
      Rails.logger.warn("[GenerateInvoicePdfJob] Rejected unexpected order_type: #{order_type}")
      return
    end

    order = order_type.constantize.find_by(id: order_id)
    return unless order

    pdf_generator = InvoicePdf.new(order)
    pdf_generator.generate
  end
end
