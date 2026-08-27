class CreateDeletionRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :deletion_requests do |t|
      t.string :requestable_type, null: false
      t.bigint :requestable_id, null: false
      t.bigint :reviewed_by_admin_id
      t.string :status, default: "pending", null: false
      t.text :reason
      t.text :rejection_reason
      t.datetime :requested_at, null: false
      t.datetime :reviewed_at
      t.datetime :password_verified_at
      t.timestamps

      t.index [:requestable_type, :requestable_id]
      t.index :reviewed_by_admin_id
      t.index :status
    end
  end
end
