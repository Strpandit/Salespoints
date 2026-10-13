class AddBankChangeRejectionReasonToDealerProfiles < ActiveRecord::Migration[8.0]
  def change
    add_column :dealer_profiles, :bank_change_rejection_reason, :text
  end
end
