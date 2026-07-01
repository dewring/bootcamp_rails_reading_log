ActiveSupport::Notifications.subscribe("cache_read.active_support") do |name, start, finish, id, payload|
  key = payload[:key]
  hit = payload[:hit]
  status = hit ? "HIT" : "MISS"
  Rails.logger.info("Cache [#{status}] for key: #{key}")
end
