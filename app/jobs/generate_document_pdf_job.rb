class GenerateDocumentPdfJob < ApplicationJob
  queue_as :pdf_reports

  ALLOWED_RECORD_TYPES = %w[Order B2bOrder Dealer AdminUser].freeze

  retry_on StandardError, attempts: 3, wait: :exponentially_longer

  def perform(document_type, record_type, record_id, options = {})
    record_type = record_type.to_s
    unless ALLOWED_RECORD_TYPES.include?(record_type)
      Rails.logger.warn("[GenerateDocumentPdfJob] Rejected unexpected record_type: #{record_type}")
      return
    end

    record = record_type.constantize.find_by(id: record_id)
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
