unless ReadingScenarioEnvironment.enabled?
  raise DevelopmentReadingScenario::ScenarioError, "Scenario seeds require development or production with ALLOW_PRODUCTION_SCENARIO=true; no records were written."
end

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
