class DevelopmentReadingScenario
  class ScenarioError < StandardError; end

  def initialize(snapshot_path: Rails.root.join("db/seeds/open_library_catalog.json"),
    manifest_path: DevelopmentReadingScenarioManifest::DEFAULT_PATH,
    lock_path: DevelopmentReadingScenarioManifest::DEFAULT_LOCK_PATH,
    as_of: DevelopmentReadingScenarioPlan.default_reference_time, password: ENV["DEVELOPMENT_SCENARIO_PASSWORD"])
    @snapshot_path = snapshot_path
    @as_of = as_of
    @scenario_manifest = DevelopmentReadingScenarioManifest.new(path: manifest_path, lock_path: lock_path, as_of: as_of)
    dependencies = { snapshot_path: snapshot_path, as_of: as_of, manifest: @scenario_manifest }
    @bootstrap = DevelopmentReadingScenarioBootstrap.new(**dependencies, password: password)
    @catalog = OpenLibraryCatalogReplay.new(**dependencies)
    @reading = DevelopmentReadingScenarioActivity.new(**dependencies)
    @community = DevelopmentReadingScenarioCommunity.new(**dependencies)
    @reactions = DevelopmentReadingScenarioReactions.new(**dependencies)
  end

  def seed_scenario
    @scenario_manifest.with_exclusive_access do
      seed_baseline
      @challenges.seed_challenges
      @reactions.seed_reactions
    end
  end

  def import_summary(manifest)
    grouped_sections = [ "bootstrap", "reading", "community", "challenges" ]
    flat_sections = [ "book_genres", "reactions" ]
    sections = manifest.slice(*grouped_sections, *flat_sections)
    counts = sections.transform_values { |section| section["actual_counts"] || section["actual_count"] }
    skipped = sections.to_h do |name, section|
      records = section.fetch("records")
      entries = if grouped_sections.include?(name)
        records.transform_values { |group| skipped_records(group) }.reject { |_group, conflicts| conflicts.empty? }
      else
        skipped_records(records)
      end
      [ name, entries ]
    end
    catalog = manifest.fetch("catalog")
    counts["catalog"] = catalog.fetch("actual_counts")
    skipped["catalog"] = catalog.slice("skipped_book_conflicts", "skipped_edition_conflicts").reject { |_group, entries| entries.empty? }
    counts["cover_previews"] = manifest.dig("cover_previews", "actual_counts") if manifest["cover_previews"]
    skipped["cover_previews"] = skipped_cover_previews(manifest.dig("cover_previews", "records") || {})
    skipped["discovery_demo"] = skipped_records(manifest.dig("reactions", "discovery_demo", "records") || {})
    { "actual_counts" => counts, "skipped" => skipped.reject { |_section, entries| entries.empty? } }
  end

  def seed_baseline
    unless ReadingScenarioEnvironment.enabled?
      raise ScenarioError, "Scenario seed replay requires development or production with ALLOW_PRODUCTION_SCENARIO=true"
    end

    @scenario_manifest.with_exclusive_access do
      catalog = OpenLibraryCatalogPreflight.new(snapshot_path: @snapshot_path, manifest_path: @scenario_manifest.path).preflight_catalog(skip_book_conflicts: true)
      @plan = DevelopmentReadingScenarioPlan.new(catalog: catalog, as_of: @as_of).build_baseline
      @manifest = @scenario_manifest.prepare_scenario(snapshot_id: catalog.fetch("snapshot_id"))
      @challenges = DevelopmentReadingScenarioChallenges.new(plan: @plan, manifest: @manifest, scenario_manifest: @scenario_manifest)
      preflight_baseline
      @bootstrap.bootstrap_scenario
      @catalog.replay_catalog
      DevelopmentReadingScenarioGenres.new(manifest: @manifest, scenario_manifest: @scenario_manifest).seed_genres
      @reading.replay_reading
      @community.replay_community
      record_baseline_result
      @scenario_manifest.save_scenario
      @manifest.deep_dup
    end
  end

  private

  def skipped_cover_previews(records)
    records.filter_map do |identity, record|
      next unless record["skip_reason"]

      [ identity, { "id" => record["book_id"], "reason" => record.fetch("skip_reason") } ]
    end.to_h
  end

  def skipped_records(records)
    records.filter_map do |identity, record|
      next unless record["result"] == "skipped"

      [ identity, record.slice("id", "reason", "record_ids", "conflicts", "edition_key") ]
    end.to_h
  end

  def preflight_baseline
    @catalog.preflight_catalog
    @bootstrap.preflight_bootstrap
    @reading.preflight_reading if @manifest["reading"]
    @community.preflight_community if @manifest["community"]
  end

  def record_baseline_result
    expected = @plan.fetch("counts")
    counts = [ "bootstrap", "catalog", "reading", "community" ].each_with_object({}) do |section, result|
      result.merge!(@manifest.fetch(section).fetch("actual_counts"))
    end.slice(*expected.keys)
    # Reading/post totals include manifest-owned ticks; the baseline targets remain explicit.
    counts["club_messages"] = @manifest.dig("community", "actual_counts", "club_messages_with_ticks")
    @manifest["baseline"] = {
      "status" => @manifest.fetch("reading").fetch("status"),
      "expected_counts" => expected, "actual_counts" => counts
    }
  end
end
