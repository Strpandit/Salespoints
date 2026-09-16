class CleanupOldBroadcastTrackersJob < ApplicationJob
  queue_as :cleanup

  RETENTION = 30.days

  RESOLVED_STATUSES = %w[accepted rejected expired].freeze

  def perform
    DealerBroadcastTracker.where(status: RESOLVED_STATUSES).where("updated_at < ?", RETENTION.ago).in_batches(of: 1000).delete_all
    OrderBroadcastTracker.where(status: RESOLVED_STATUSES).where("updated_at < ?", RETENTION.ago).in_batches(of: 1000).delete_all
  end
end
