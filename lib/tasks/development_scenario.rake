namespace :development_scenario do
  desc "Replay 150 library entries and 300 dated sessions offline (development only)"
  task replay_reading: :environment do
    manifest = DevelopmentReadingScenarioActivity.new.replay_reading
    $stdout.write("Reading rows saved: #{manifest.fetch('reading').fetch('actual_counts').to_json}\n")
    $stdout.write("Run the development worker, then development_scenario:reconcile_reading before recording final truth.\n")
  rescue DevelopmentReadingScenarioActivity::ActivityError, OpenLibraryCatalogPreflight::PreflightError => error
    abort error.message
  end

  desc "Check callback jobs and final scenario library states without bypassing the worker (development only)"
  task reconcile_reading: :environment do
    manifest = DevelopmentReadingScenarioActivity.new.reconcile_reading
    reading = manifest.fetch("reading")
    $stdout.write("Reading status: #{reading.fetch('status')}; callback work: #{reading.fetch('callback_work').to_json}\n")
  rescue DevelopmentReadingScenarioActivity::ActivityError, OpenLibraryCatalogPreflight::PreflightError => error
    abort error.message
  end

  desc "Bootstrap synthetic readers, genres and badges with safe resume (development only)"
  task bootstrap_scenario: :environment do
    manifest = DevelopmentReadingScenarioBootstrap.new.bootstrap_scenario
    $stdout.write("Bootstrap complete: #{manifest.fetch('bootstrap').fetch('actual_counts').to_json}\n")
    $stdout.write("Credentials come from DEVELOPMENT_SCENARIO_PASSWORD; plaintext passwords are not stored in the manifest.\n")
  rescue DevelopmentReadingScenarioBootstrap::BootstrapError, OpenLibraryCatalogPreflight::PreflightError => error
    $stderr.write("#{error.message}\n")
    abort "Scenario bootstrap stopped; review the reported identity or configuration before retrying."
  end

  desc "Preview the deterministic Week 15 baseline inventory without writing records (development only)"
  task plan_baseline: :environment do
    catalog = OpenLibraryCatalogPreflight.new.preflight_catalog
    plan = DevelopmentReadingScenarioPlan.new(catalog: catalog).build_baseline
    $stdout.write("Baseline plan: #{plan.fetch('counts').to_json}\n")
    $stdout.write("Seed: #{plan.fetch('seed')}; as_of: #{plan.fetch('as_of')}\n")
    $stdout.write("No database records were changed.\n")
  rescue OpenLibraryCatalogPreflight::PreflightError => error
    $stderr.write("#{error.message}\n")
    $stderr.write("#{JSON.pretty_generate(error.report.fetch('conflicts', []))}\n")
    abort "Baseline planning stopped."
  end

  desc "Replay the captured catalog offline with a resumable local manifest (development only)"
  task replay_catalog: :environment do
    manifest = OpenLibraryCatalogReplay.new.replay_catalog
    catalog = manifest.fetch("catalog")
    $stdout.write("Catalog replay complete: #{catalog.fetch('actual_counts').to_json}\n")
    $stdout.write("Snapshot ID: #{manifest.fetch('snapshot_id')}; seed: #{manifest.fetch('seed')}; as_of: #{manifest.fetch('as_of')}\n")
    $stdout.write("Manifest: #{Rails.root.join('storage/development_scenarios/week15.json')}\n")
  rescue OpenLibraryCatalogReplay::ReplayError, OpenLibraryCatalogPreflight::PreflightError => error
    $stderr.write("#{error.message}\n")
    if error.is_a?(OpenLibraryCatalogPreflight::PreflightError)
      $stderr.write("#{JSON.pretty_generate(error.report.fetch('conflicts', []))}\n")
    end
    abort "Catalog replay stopped; preserve the manifest and resolve the reported conflict before retrying."
  end

  desc "Inspect the saved catalog and report identity collisions without writing records (development only)"
  task preflight_catalog: :environment do
    report = OpenLibraryCatalogPreflight.new.preflight_catalog
    books = report.fetch("books")
    $stdout.write("Snapshot ID: #{report.fetch('snapshot_id')}\n")
    $stdout.write("Works checked: #{books.length}; existing Works to reuse: #{books.count { |book| book.fetch('book_status') == 'reused' }}\n")
    $stdout.write("Works without representative Editions: #{books.count { |book| book.fetch('edition_status') == 'skipped' }}\n")
    $stdout.write("Preflight passed. No database records were changed.\n")
  rescue OpenLibraryCatalogPreflight::PreflightError => error
    $stderr.write("#{error.message}\n")
    $stderr.write("#{JSON.pretty_generate(error.report.fetch('conflicts', []))}\n")
    abort "Catalog preflight failed."
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
