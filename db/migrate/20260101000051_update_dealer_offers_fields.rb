class UpdateDealerOffersFields < ActiveRecord::Migration[8.0]
  def change
    remove_column :dealer_offers, :offer_name, :string if column_exists?(:dealer_offers, :offer_name)
    remove_column :dealer_offers, :seller_price, :decimal if column_exists?(:dealer_offers, :seller_price)
    remove_column :dealer_offers, :colour, :string if column_exists?(:dealer_offers, :colour)
    remove_column :dealer_offers, :brand_name, :string if column_exists?(:dealer_offers, :brand_name)
    remove_column :dealer_offers, :mrp, :decimal if column_exists?(:dealer_offers, :mrp)
    remove_column :dealer_offers, :ram_storage, :string if column_exists?(:dealer_offers, :ram_storage)

    add_column :dealer_offers, :reuploaded_at, :datetime unless column_exists?(:dealer_offers, :reuploaded_at)
    add_column :dealer_offers, :slug, :string unless column_exists?(:dealer_offers, :slug)
    add_index :dealer_offers, :slug, unique: true unless index_exists?(:dealer_offers, :slug)
  end
end
