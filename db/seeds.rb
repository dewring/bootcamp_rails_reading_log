unless Rails.env.development?
  raise DevelopmentReadingScenario::ScenarioError, "Development scenario seeds are only available in development; no records were written."
end

manifest = DevelopmentReadingScenario.new.seed_baseline
baseline = manifest.fetch("baseline")
$stdout.write("Development baseline: #{baseline.fetch('status')}\n")
$stdout.write("Scenario-owned counts: #{baseline.fetch('actual_counts').to_json}\n")
$stdout.write("Run the development worker and replay seeds to verify final truth after callback jobs drain.\n")
