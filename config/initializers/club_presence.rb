require "redis"
require "connection_pool"

# Share Redis clients between subscriptions without holding one per open tab.
Rails.application.config.x.club_presence.redis_pool = ConnectionPool.new(
  size: ENV.fetch("RAILS_MAX_THREADS", 5).to_i,
  timeout: 1
) do
  Redis.new(
    url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1"),
    connect_timeout: 1,
    read_timeout: 1,
    write_timeout: 1
  )
end
