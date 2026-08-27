class GenerateDocumentPdfJob < ApplicationJob
  queue_as :pdf_reports

  retry_on StandardError, attempts: 3, wait: :exponentially_longer

  def perform(document_type, record_type, record_id, options = {})
    record = record_type.to_s.constantize.find_by(id: record_id)
    return unless record

    case document_type.to_s.to_sym
    when :invoice
      InvoicePdf.new(record).generate
    when :delivery_order
      DeliveryOrderPdf.new(record).generate
    when :dealer_agreement
      DealerAgreementPdfService.generate(record)
    when :offer_letter
      AdminOfferLetterPdf.new(record).render
    else
      Rails.logger.warn("Unknown document type in GenerateDocumentPdfJob: #{document_type}")
    end
  end
end
