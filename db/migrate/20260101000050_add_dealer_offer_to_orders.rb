class AddDealerOfferToOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :orders, :dealer_offer_id, :bigint
    add_index :orders, :dealer_offer_id
  end
end
