class AddBankChangeFieldsToDealerProfiles < ActiveRecord::Migration[8.0]
  def change
    add_column :dealer_profiles, :bank_change_status, :string, default: "none", null: false
    add_column :dealer_profiles, :bank_change_requested_at, :datetime
    add_column :dealer_profiles, :bank_change_reason, :text
    add_column :dealer_profiles, :bank_change_reviewed_at, :datetime
    add_column :dealer_profiles, :bank_change_reviewed_by_id, :integer

    add_index :dealer_profiles, :bank_change_status
    add_index :dealer_profiles, :bank_change_reviewed_by_id
  end
end
