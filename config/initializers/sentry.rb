Sentry.init do |config|
  config.dsn = ENV["GLITCHTIP_DSN"]
  config.traces_sample_rate = 1.0
  config.enabled_environments = %w[production development]
  config.release = ENV["SOURCE_COMMIT"]
end
