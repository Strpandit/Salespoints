module Reports
  class OrderFinancials
    NON_SALE_STATUSES = %w[cancelled returned rejected_request].freeze
    NON_SALE_PAYMENT_STATUSES = %w[failed refunded].freeze

    def initialize
      @service = DealerPayoutService.new
    end

    def resolve(order)
      stored_comm = order.try(:commission_amount).to_d
      stored_net  = order.try(:seller_settlement_amount).to_d
      return [stored_comm, stored_net] unless stored_comm.zero? || stored_net.zero?
      return [stored_comm, stored_net] unless live_sale?(order)

      fin = @service.calculate_order_financials(order)
      [
        stored_comm.zero? ? fin[:commission_fee].to_d : stored_comm,
        stored_net.zero? ? fin[:net_payout_amount].to_d : stored_net
      ]
    rescue StandardError => e
      Rails.logger.warn("[Reports::OrderFinancials] #{order.class.name}##{order.try(:id)}: #{e.class}: #{e.message}")
      [order.try(:commission_amount).to_d, order.try(:seller_settlement_amount).to_d]
    end

    private

    def live_sale?(order)
      return false if NON_SALE_STATUSES.include?(order.try(:status).to_s)
      return false if NON_SALE_PAYMENT_STATUSES.include?(order.try(:payment_status).to_s)
      return false if order.try(:refund_status).to_s == "completed"

      true
    end
  end
end
