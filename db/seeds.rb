unless Rails.env.development?
  raise DevelopmentReadingScenario::ScenarioError, "Development scenario seeds are only available in development; no records were written."
end

manifest = DevelopmentReadingScenario.new.seed_scenario
baseline = manifest.fetch("baseline")
$stdout.write("Development baseline: #{baseline.fetch('status')}\n")
$stdout.write("Scenario-owned counts: #{baseline.fetch('actual_counts').to_json}\n")
$stdout.write("Scenario-owned reactions: #{manifest.fetch('reactions').fetch('actual_counts').to_json}\n")
$stdout.write("Run the development worker to process normal background jobs.\n")
