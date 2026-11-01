class DevelopmentReadingScenario
  class ScenarioError < StandardError; end

  def initialize(snapshot_path: Rails.root.join("db/seeds/open_library_catalog.json"),
    manifest_path: Rails.root.join("storage/development_scenarios/week15.json"),
    lock_path: Rails.root.join("storage/development_scenarios/week15.lock"),
    as_of: Time.zone.local(2026, 10, 30, 12), password: ENV["DEVELOPMENT_SCENARIO_PASSWORD"])
    @snapshot_path = snapshot_path
    @as_of = as_of
    @scenario_manifest = DevelopmentReadingScenarioManifest.new(path: manifest_path, lock_path: lock_path, as_of: as_of)
    dependencies = { snapshot_path: snapshot_path, as_of: as_of, manifest: @scenario_manifest }
    @bootstrap = DevelopmentReadingScenarioBootstrap.new(**dependencies, password: password)
    @catalog = OpenLibraryCatalogReplay.new(**dependencies)
    @reading = DevelopmentReadingScenarioActivity.new(**dependencies)
    @community = DevelopmentReadingScenarioCommunity.new(**dependencies)
  end

  def seed_baseline
    raise ScenarioError, "Scenario seed replay is only available in development" unless Rails.env.development?

    @scenario_manifest.with_exclusive_access do
      catalog = OpenLibraryCatalogPreflight.new(snapshot_path: @snapshot_path).preflight_catalog
      @plan = DevelopmentReadingScenarioPlan.new(catalog: catalog, as_of: @as_of).build_baseline
      @manifest = @scenario_manifest.prepare_scenario(snapshot_id: catalog.fetch("snapshot_id"))
      preflight_baseline
      @bootstrap.bootstrap_scenario
      @catalog.replay_catalog
      @reading.replay_reading
      @community.replay_community
      @reading.reconcile_reading
      record_baseline_result
      @scenario_manifest.save_scenario
      @manifest.deep_dup
    end
  rescue DevelopmentReadingScenarioManifest::ManifestError, OpenLibraryCatalogPreflight::PreflightError,
    DevelopmentReadingScenarioBootstrap::BootstrapError, OpenLibraryCatalogReplay::ReplayError,
    DevelopmentReadingScenarioActivity::ActivityError, DevelopmentReadingScenarioCommunity::CommunityError => error
    raise ScenarioError, error.message
  end

  private

  def preflight_baseline
    @catalog.preflight_catalog
    @bootstrap.preflight_bootstrap
    @reading.preflight_reading(allow_incomplete: true) if @manifest["reading"]
    if @manifest["community"]
      @community.preflight_community
      return
    end

    names = @plan.fetch("book_clubs").map { |entry| entry.fetch("attributes").fetch("name").downcase }
    collisions = BookClub.where("LOWER(name) IN (?)", names).pluck(:id)
    actor_ids = @manifest.dig("bootstrap", "records", "users")&.values&.filter_map { |record| record["id"] } || []
    existing = {
      "book_clubs" => collisions,
      "book_club_memberships" => BookClubMembership.where(user_id: actor_ids).pluck(:id),
      "club_messages" => ClubMessage.where(user_id: actor_ids).pluck(:id),
      "reviews" => Review.where(user_id: actor_ids).pluck(:id)
    }.reject { |_group, ids| ids.empty? }
    raise ScenarioError, "Unrecorded community data or club-name collisions: #{existing.inspect}; review before importing any baseline records." if existing.any?

    return if @manifest["reading"]

    reading = { "user_books" => UserBook.where(user_id: actor_ids).pluck(:id), "reading_sessions" => ReadingSession.where(user_id: actor_ids).pluck(:id) }
      .reject { |_group, ids| ids.empty? }
    raise ScenarioError, "Unrecorded reading data: #{reading.inspect}; review before importing any baseline records." if reading.any?
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
