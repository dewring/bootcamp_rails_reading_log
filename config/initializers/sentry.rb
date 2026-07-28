Sentry.init do |config|
  config.dsn = ENV["SENTRY_DSN"]
  config.traces_sample_rate = 1.0
  config.enabled_environments = %w[production]
end
