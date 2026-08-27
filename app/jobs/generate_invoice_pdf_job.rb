class GenerateInvoicePdfJob < ApplicationJob
  queue_as :pdf_reports

  retry_on StandardError, attempts: 3, wait: :exponentially_longer

  def perform(order_id, order_type = "Order")
    order = order_type.to_s.constantize.find_by(id: order_id)
    return unless order

    pdf_generator = InvoicePdf.new(order)
    pdf_generator.generate
  end
end
