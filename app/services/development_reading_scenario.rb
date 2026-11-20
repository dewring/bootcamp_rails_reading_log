class DevelopmentReadingScenario
  def initialize(snapshot_path: Rails.root.join("db/seeds/open_library_catalog.json"),
    manifest_path: DevelopmentReadingScenarioManifest::DEFAULT_PATH,
    as_of: nil, password: ENV["DEVELOPMENT_SCENARIO_PASSWORD"])
    @snapshot_path = snapshot_path
    @manifest_path = manifest_path
    @as_of = as_of
    @password = password
  end

  def seed_scenario
    as_of = @as_of || DevelopmentReadingScenarioPlan.configured_reference_time
    store = DevelopmentReadingScenarioManifest.new(path: @manifest_path, as_of: as_of)
    manifest = OpenLibraryCatalogReplay.new(snapshot_path: @snapshot_path, manifest: store, as_of: as_of).replay_catalog
    plan = DevelopmentReadingScenarioPlan.new(as_of: Time.iso8601(manifest.fetch("as_of"))).static_records(
      recorded_users: manifest.dig("bootstrap", "records", "users") || {}
    )
    inputs = { manifest: manifest, scenario_manifest: store }
    DevelopmentReadingScenarioBootstrap.new(**inputs, plan: plan, password: @password).bootstrap_scenario
    DevelopmentReadingScenarioGenres.new(**inputs).seed_genres
    DevelopmentReadingScenarioChallenges.new(**inputs, plan: plan).seed_challenges
    activity = DevelopmentReadingScenarioActivity.new(**inputs).simulate_reading
    import_summary(manifest, activity)
  rescue DevelopmentReadingScenarioManifest::ManifestError, OpenLibraryCatalogPreflight::PreflightError,
    OpenLibraryCatalogReplay::ReplayError, DevelopmentReadingScenarioCoverPreviews::PreviewError,
    DevelopmentReadingScenarioBootstrap::BootstrapError, DevelopmentReadingScenarioPlan::ReferenceTimeError => error
    { "status" => "stopped", "reason" => error.message }
  end

  private

  def import_summary(manifest, activity)
    catalog = manifest.fetch("catalog")
    counts = catalog.fetch("actual_counts").merge(manifest.dig("bootstrap", "actual_counts"), manifest.dig("challenges", "actual_counts"))
    counts["book_genres"] = manifest.dig("book_genres", "actual_count")
    skipped = activity.fetch("skipped")
    [ "bootstrap", "challenges" ].each do |section|
      manifest.fetch(section).fetch("records").each do |group, records|
        records.each do |identity, record|
          skipped["#{group}/#{identity}"] = record["reason"] if [ "failed", "skipped" ].include?(record["result"])
        end
      end
    end
    manifest.dig("book_genres", "records").each do |identity, record|
      skipped["book_genres/#{identity}"] = record["reason"] if [ "failed", "skipped" ].include?(record["result"])
    end
    catalog.fetch("records").each do |work, pair|
      [ "book", "edition" ].each do |kind|
        record = pair.fetch(kind)
        skipped["#{work}/#{kind}"] = record["errors"] if record["result"] == "failed"
      end
    end
    catalog.slice("skipped_book_conflicts", "skipped_edition_conflicts").each do |group, conflicts|
      skipped[group] = conflicts if conflicts.any?
    end
    { "status" => skipped.empty? ? "complete" : "partial", "static_counts" => counts, "added" => activity.fetch("added"), "skipped" => skipped }
  end
end
