namespace :development_scenario do
  desc "Refresh one recorded old_hit reaction once using the scenario reference time (development only)"
  task refresh_old_hit_reaction: :environment do
    manifest = DevelopmentReadingScenarioReactions.new.refresh_old_hit_reaction
    action = manifest.fetch("reactions").fetch(DevelopmentReadingScenarioReactions::REFRESH_ACTION)
    $stdout.write("Old-hit reaction refresh #{action.fetch('status')}; reaction ID: #{action.fetch('reaction_id')}.\n")
    $stdout.write("Ranking reference time: #{manifest.fetch('as_of')}; reaction updated_at: #{action.fetch('updated_at')}.\n")
    $stdout.write("The scenario-owned old_hit score at this reference time increases from 2 to 3. Repeating this command preserves the timestamp.\n")
    $stdout.write("The homepage uses its current request time; old scenario dates may fall outside its seven-day window.\n")
  rescue DevelopmentReadingScenarioReactions::ReactionsError, DevelopmentReadingScenarioManifest::ManifestError => error
    abort error.message
  end

  desc "Seed 160 owned book reactions from the prepared baseline (development only)"
  task seed_reactions: :environment do
    manifest = DevelopmentReadingScenarioReactions.new.seed_reactions
    $stdout.write("Scenario-owned reactions: #{manifest.fetch('reactions').fetch('actual_counts').to_json}\n")
    $stdout.write("Run the development worker to publish aggregate totals.\n")
  rescue DevelopmentReadingScenarioReactions::ReactionsError, DevelopmentReadingScenarioManifest::ManifestError => error
    abort error.message
  end

  desc "Simulate reading activity once: three sessions and two top-level posts (development only)"
  task simulate_reading: :environment do
    name = DevelopmentReadingScenarioTick::Plan::NAME
    manifest = DevelopmentReadingScenarioTick.new.advance_scenario(tick: name)
    tick = manifest.fetch("ticks").fetch(name)
    $stdout.write("Baseline activity: #{tick.fetch('baseline_counts').to_json}\n")
    $stdout.write("Reading simulation #{tick.fetch('status')}; scenario counts: #{tick.fetch('scenario_counts').to_json}\n")
    $stdout.write("Run the development worker to process normal background jobs.\n")
  rescue DevelopmentReadingScenarioTick::TickError => error
    abort error.message
  end

  desc "Capture 100 Open Library Works for offline development seed replay (development only)"
  task capture_catalog: :environment do
    snapshot = OpenLibraryCatalogCapture.new.capture_catalog
    $stdout.write("Captured #{snapshot.fetch('selected').length} Works in #{snapshot.fetch('http_attempts')} HTTP attempts.\n")
    $stdout.write("Snapshot: #{Rails.root.join('db/seeds/open_library_catalog.json')}\n")
    $stdout.write("Snapshot ID: #{snapshot.fetch('snapshot_id')}\n")
    $stdout.write("Skipped records: #{snapshot.fetch('skipped').length}\n")
    snapshot.fetch("skipped").each { |record| $stdout.write("#{record.to_json}\n") }
  rescue OpenLibraryCatalogCapture::CaptureError => error
    $stderr.write("#{error.message}\n")
    $stderr.write("#{JSON.pretty_generate(error.report)}\n")
    abort "Catalog capture failed."
  end
end
