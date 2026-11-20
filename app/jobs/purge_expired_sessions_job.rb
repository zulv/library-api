class PurgeExpiredSessionsJob < ApplicationJob
  def perform
    purged_count = Session.purge_expired
    logger.info "Purged #{purged_count} expired sessions"
  end
end
