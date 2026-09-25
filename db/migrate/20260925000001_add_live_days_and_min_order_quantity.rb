class AddLiveDaysAndMinOrderQuantity < ActiveRecord::Migration[8.0]
  def change
    add_column :wholesaler_posts, :live_days, :integer, default: 7, null: false
    add_column :wholesaler_posts, :min_order_quantity, :integer, default: 2, null: false
    add_column :dealer_offers, :live_days, :integer, default: 7, null: false
  end
end
