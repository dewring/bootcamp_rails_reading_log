# Rails can load this file as part of db:prepare when provisioning a database.
return if Rails.env.production?

manifest = DevelopmentReadingScenario.new.seed_scenario
baseline = manifest.fetch("baseline")
$stdout.write("Scenario baseline: #{baseline.fetch('status')}\n")
$stdout.write("Scenario reference time: #{manifest.fetch('as_of')}\n")
$stdout.write("Scenario-owned counts: #{baseline.fetch('actual_counts').to_json}\n")
$stdout.write("Scenario baseline reactions: #{manifest.fetch('reactions').fetch('actual_counts').to_json}\n")
$stdout.write("Current synthetic-reader reactions: #{manifest.fetch('reactions').fetch('current_counts').to_json}\n")
$stdout.write("Scenario challenges: #{manifest.fetch('challenges').fetch('actual_counts').to_json}\n")
$stdout.write("Scenario genre links: #{manifest.fetch('book_genres').fetch('actual_count')}\n")
$stdout.write("Run the application worker to process normal background jobs.\n")
