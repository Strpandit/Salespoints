class CreateActiveStorageTables < ActiveRecord::Migration[8.0]
  def change
    enable_extension "pg_catalog.plpgsql" unless extension_enabled?("pg_catalog.plpgsql")

    create_table :active_storage_blobs do |t|
      t.string :key, null: false
      t.string :filename, null: false
      t.string :content_type
      t.text :metadata
      t.string :service_name, null: false
      t.bigint :byte_size, null: false
      t.string :checksum, null: false
      t.timestamps

      t.index :key, unique: true
    end

    create_table :active_storage_attachments do |t|
      t.string :name, null: false
      t.string :record_type, null: false
      t.bigint :record_id, null: false
      t.bigint :blob_id, null: false
      t.timestamps

      t.index :blob_id
      t.index [:record_type, :record_id, :name, :blob_id], name: "index_active_storage_attachments_uniqueness", unique: true

      t.foreign_key :active_storage_blobs, column: :blob_id
    end

    create_table :active_storage_variant_records do |t|
      t.bigint :blob_id, null: false
      t.string :variation_digest, null: false
      t.timestamps

      t.index [:blob_id, :variation_digest], name: "index_active_storage_variant_records_uniqueness", unique: true

      t.foreign_key :active_storage_blobs, column: :blob_id
    end
  end
end
