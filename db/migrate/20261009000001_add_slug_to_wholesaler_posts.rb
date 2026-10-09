class AddSlugToWholesalerPosts < ActiveRecord::Migration[8.0]
  class MigrationPost < ActiveRecord::Base
    self.table_name = "wholesaler_posts"
  end

  def up
    add_column :wholesaler_posts, :slug, :string

    MigrationPost.reset_column_information
    MigrationPost.find_each do |post|
      base = post.title.to_s.parameterize.presence || "bulk-deal"
      post.update_columns(slug: "#{base}-#{SecureRandom.hex(3)}")
    end

    add_index :wholesaler_posts, :slug, unique: true
  end

  def down
    remove_index :wholesaler_posts, :slug
    remove_column :wholesaler_posts, :slug
  end
end
