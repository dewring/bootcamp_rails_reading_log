# db:prepare also loads this file when provisioning production.
return if Rails.env.production?

puts JSON.pretty_generate(DevelopmentReadingScenario.new.seed_scenario)
