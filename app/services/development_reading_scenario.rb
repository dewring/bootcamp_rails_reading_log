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

  def seed_baseline
    unless ReadingScenarioEnvironment.enabled?
      raise ScenarioError, "Scenario seed replay requires development or production with ALLOW_PRODUCTION_SCENARIO=true"
    end

    @scenario_manifest.with_exclusive_access do
      catalog = OpenLibraryCatalogPreflight.new(snapshot_path: @snapshot_path, manifest_path: @scenario_manifest.path).preflight_catalog(skip_book_conflicts: true)
      @plan = DevelopmentReadingScenarioPlan.new(catalog: catalog, as_of: @as_of).build_baseline
      @manifest = @scenario_manifest.prepare_scenario(snapshot_id: catalog.fetch("snapshot_id"))
      @challenges = DevelopmentReadingScenarioChallenges.new(plan: @plan, manifest: @manifest, scenario_manifest: @scenario_manifest)
      @challenges.preflight_challenges
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
