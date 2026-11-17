unless ReadingScenarioEnvironment.enabled?
  raise DevelopmentReadingScenario::ScenarioError, "Scenario seeds require development or production with ALLOW_PRODUCTION_SCENARIO=true; no records were written."
end

manifest = DevelopmentReadingScenario.new.seed_scenario
baseline = manifest.fetch("baseline")
$stdout.write("Development baseline: #{baseline.fetch('status')}\n")
$stdout.write("Scenario-owned counts: #{baseline.fetch('actual_counts').to_json}\n")
$stdout.write("Scenario baseline reactions: #{manifest.fetch('reactions').fetch('actual_counts').to_json}\n")
$stdout.write("Current synthetic-reader reactions: #{manifest.fetch('reactions').fetch('current_counts').to_json}\n")
$stdout.write("Run the development worker to process normal background jobs.\n")
