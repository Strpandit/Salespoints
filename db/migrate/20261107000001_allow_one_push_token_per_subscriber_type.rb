class AllowOnePushTokenPerSubscriberType < ActiveRecord::Migration[8.0]
  def up
    remove_index :push_subscriptions, name: "index_push_subscriptions_on_token", if_exists: true
    add_index :push_subscriptions, :token, name: "index_push_subscriptions_on_token"
    add_index :push_subscriptions, %i[token subscriber_type], unique: true,
              name: "index_push_subscriptions_on_token_and_subscriber_type"
  end

  def down
    remove_index :push_subscriptions, name: "index_push_subscriptions_on_token_and_subscriber_type", if_exists: true
    remove_index :push_subscriptions, name: "index_push_subscriptions_on_token", if_exists: true
    execute <<~SQL.squish
      DELETE FROM push_subscriptions a USING push_subscriptions b
      WHERE a.token = b.token AND a.id < b.id
    SQL
    add_index :push_subscriptions, :token, unique: true, name: "index_push_subscriptions_on_token"
  end
end
