require "test_helper"
require "tmpdir"

class DevelopmentReadingScenarioBootstrapTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  self.use_transactional_tests = false

  setup do
    @initial_user_ids = User.pluck(:id)
    @initial_book_ids = Book.pluck(:id)
    @initial_genres = Genre.all.map(&:attributes)
    @initial_badges = Badge.all.map(&:attributes)
    @directory = Pathname.new(Dir.mktmpdir("booknook-scenario-bootstrap-"))
    @snapshot_path = @directory.join("catalog.json")
    @manifest_path = @directory.join("state/reading_scenario.json")
    @lock_path = @directory.join("state/reading_scenario.lock")
    @password = "synthetic-scenario-test-password"
    @docs = Array.new(100) do |index|
      { "key" => "/works/OL#{155_000 + index}W", "title" => "Bootstrap source #{index + 1}", "author_name" => [ "Source Author" ] }
    end
    @bootstrap = build_bootstrap
  end

  teardown do
    User.where.not(id: @initial_user_ids).find_each(&:destroy!)
    Book.where.not(id: @initial_book_ids).find_each(&:destroy!)
    restore_shared_records(Genre, @initial_genres)
    restore_shared_records(Badge, @initial_badges)
    FileUtils.remove_entry(@directory)
  end

  test "bootstrap creates 30 readers and one admin while retaining all genre and badge types" do
    write_snapshot
    initial_users = User.count
    existing_genres = Genre.all.map(&:attributes)
    existing_badges = Badge.all.map(&:attributes)
    manifest = nil

    assert_no_enqueued_jobs do
      manifest = bootstrap_scenario
    end

    assert_equal initial_users + 31, User.count
    assert_equal({ "genres" => 12, "badges" => 5, "users" => 31 }, manifest.fetch("bootstrap").fetch("actual_counts"))
    assert_equal "complete", manifest.fetch("bootstrap").fetch("status")
    ids = user_records(manifest).values.map { |record| record.fetch("id") }
    users = User.where(id: ids)
    assert_equal 30, users.where(role: "user").count
    assert_equal 1, users.where(role: "admin").count
    assert_equal 31, users.where(account_status: "active").count
    assert users.all? { |user| user.email.end_with?("@example.test") && user.valid_password?(@password) }
    reader = User.find(user_records(manifest).fetch("reader01").fetch("id"))
    assert_equal [ "Maya", "Chen", "maya.chen" ], [ reader.first_name, reader.last_name, reader.nickname ]
    admin = User.find(user_records(manifest).fetch("admin").fetch("id"))
    assert_equal [ "Avery", "Morgan", "avery.morgan" ], [ admin.first_name, admin.last_name, admin.nickname ]
    assert_equal 0, WebhookEndpoint.where(user_id: ids).count
    existing_genres.each { |attributes| assert_equal attributes, Genre.find(attributes.fetch("id")).attributes }
    existing_badges.each { |attributes| assert_equal attributes, Badge.find(attributes.fetch("id")).attributes }
    assert_equal manifest, JSON.parse(@manifest_path.read)
    assert_not_includes @manifest_path.read, @password
    assert_equal 0, @manifest_path.stat.mode & 0o077
    assert_not_requested :any, /https?:/
  end

  test "replaying completed bootstrap needs no password and preserves all IDs and record attributes" do
    write_snapshot
    first = bootstrap_scenario
    before = User.order(:id).map(&:attributes)
    without_password = build_bootstrap(password: nil)

    second = Rails.stub(:env, "development".inquiry) { without_password.bootstrap_scenario }

    assert_equal bootstrap_ids(first), bootstrap_ids(second)
    assert_equal before, User.order(:id).map(&:attributes)
    assert user_records(second).values.all? { |record| record.fetch("result") == "reused" }
  end

  test "an existing reader email is refused before creating genres badges or accounts" do
    collision = User.create!(
      first_name: "Existing", last_name: "Person", nickname: "existing_person",
      email: "reader01@example.test", password: @password, role: "user", account_status: "active"
    )
    before = collision.attributes
    write_snapshot

    assert_no_difference [ "Genre.count", "Badge.count", "User.count" ] do
      error = assert_raises(DevelopmentReadingScenarioBootstrap::BootstrapError) { bootstrap_scenario }
      assert_includes error.message, collision.id.to_s
      assert_includes error.message, "no automatic merge or account takeover"
    end
    assert_equal before, collision.reload.attributes
    assert_not @manifest_path.exist?
  end

  test "a collision at the final admin nickname cannot cause an account takeover or earlier writes" do
    collision = User.create!(
      first_name: "Existing", last_name: "Reader", nickname: "avery.morgan",
      email: "someone@example.test", password: @password, role: "user", account_status: "active"
    )
    write_snapshot

    assert_no_difference [ "Genre.count", "Badge.count", "User.count" ] do
      error = assert_raises(DevelopmentReadingScenarioBootstrap::BootstrapError) { bootstrap_scenario }
      assert_includes error.message, collision.id.to_s
    end
    assert_equal "user", collision.reload.role
    assert_not @manifest_path.exist?
  end

  test "matching synthetic attributes and a matching password do not make an unrecorded account scenario-owned" do
    write_snapshot
    plan = scenario_plan
    attributes = plan.fetch("users").first.fetch("attributes")
    existing = User.create!(attributes.merge("password" => @password))

    assert_no_difference "User.count" do
      error = assert_raises(DevelopmentReadingScenarioBootstrap::BootstrapError) { bootstrap_scenario }
      assert_includes error.message, existing.id.to_s
    end
    assert_not @manifest_path.exist?
  end

  test "a missing password is refused before writing bootstrap records or a manifest" do
    write_snapshot
    bootstrap = build_bootstrap(password: nil)

    assert_no_difference [ "Genre.count", "Badge.count", "User.count" ] do
      Rails.stub(:env, "development".inquiry) do
        error = assert_raises(DevelopmentReadingScenarioBootstrap::BootstrapError) { bootstrap.bootstrap_scenario }
        assert_includes error.message, "DEVELOPMENT_SCENARIO_PASSWORD"
      end
    end
    assert_not @manifest_path.exist?
  end

  test "password validation remains active before any records are created" do
    write_snapshot
    bootstrap = build_bootstrap(password: "x")

    assert_no_difference [ "Genre.count", "Badge.count", "User.count" ] do
      Rails.stub(:env, "development".inquiry) do
        assert_raises(DevelopmentReadingScenarioBootstrap::BootstrapError) { bootstrap.bootstrap_scenario }
      end
    end
    assert_not @manifest_path.exist?
  end

  test "an account committed before its manifest update resumes only with its original planned Devise hash" do
    write_snapshot
    interrupt_after_first_account_commit
    user = User.find_by!(email: "reader01@example.test")
    manifest = JSON.parse(@manifest_path.read)
    recorded = user_records(manifest).fetch("reader01")
    assert_nil recorded.fetch("id")
    assert_equal user.encrypted_password, recorded.fetch("expected_attributes").fetch("encrypted_password")
    first_id = user.id

    completed = bootstrap_scenario

    assert_equal first_id, user_records(completed).fetch("reader01").fetch("id")
    assert_equal @initial_user_ids.length + 31, User.count
    assert_equal bootstrap_ids(completed), bootstrap_ids(bootstrap_scenario)
    assert_not_requested :any, /https?:/
  end

  test "changed scenario credentials stop resume before unfinished users are created" do
    write_snapshot
    interrupt_after_first_account_commit
    user = User.find_by!(email: "reader01@example.test")
    user.update!(password: "a-different-synthetic-password")
    before = @manifest_path.binread

    assert_no_difference [ "Genre.count", "Badge.count", "User.count" ] do
      error = assert_raises(DevelopmentReadingScenarioBootstrap::BootstrapError) { bootstrap_scenario }
      assert_includes error.message, user.id.to_s
      assert_includes error.message, "changed"
    end
    assert_equal before, @manifest_path.binread
    assert_not User.exists?(email: "reader02@example.test")
  end

  test "the wrong local password cannot resume creation of unfinished synthetic accounts" do
    write_snapshot
    interrupt_after_first_account_commit
    wrong_password = build_bootstrap(password: "another-local-test-password")
    before = @manifest_path.binread

    assert_no_difference "User.count" do
      Rails.stub(:env, "development".inquiry) do
        error = assert_raises(DevelopmentReadingScenarioBootstrap::BootstrapError) { wrong_password.bootstrap_scenario }
        assert_includes error.message, "password differs"
      end
    end
    assert_equal before, @manifest_path.binread
  end

  test "a missing recorded password hash refuses resume without adopting an account by public attributes" do
    write_snapshot
    interrupt_after_first_account_commit
    manifest = JSON.parse(@manifest_path.read)
    user_records(manifest).fetch("reader01").fetch("expected_attributes").delete("encrypted_password")
    @manifest_path.write(JSON.pretty_generate(manifest))

    assert_no_difference "User.count" do
      assert_raises(DevelopmentReadingScenarioBootstrap::BootstrapError) { bootstrap_scenario }
    end
  end

  test "a deleted recorded user is not silently recreated" do
    write_snapshot
    manifest = bootstrap_scenario
    id = user_records(manifest).fetch("reader30").fetch("id")
    User.find(id).destroy!

    assert_no_difference "User.count" do
      error = assert_raises(DevelopmentReadingScenarioBootstrap::BootstrapError) { bootstrap_scenario }
      assert_includes error.message, id.to_s
      assert_includes error.message, "no automatic recreation"
    end
  end

  test "a user edited after preflight is rechecked before its replay checkpoint without overwriting the edit" do
    write_snapshot
    manifest = bootstrap_scenario
    user = User.find(user_records(manifest).fetch("reader01").fetch("id"))
    original_rename = File.method(:rename)
    edited = false

    File.stub(:rename, ->(source, destination) {
      original_rename.call(source, destination)
      unless edited
        edited = true
        user.update!(first_name: "Developer edit")
      end
    }) do
      error = assert_raises(DevelopmentReadingScenarioBootstrap::BootstrapError) { bootstrap_scenario }
      assert_includes error.message, user.id.to_s
      assert_includes error.message, "changed"
    end

    assert_equal "Developer edit", user.reload.first_name
  end

  test "a missing badge is recreated from the retained bootstrap defaults through normal validation" do
    missing = Badge.find_by!(badge_type: "first_session")
    missing.destroy!
    write_snapshot

    manifest = bootstrap_scenario

    badge = Badge.find(manifest.fetch("bootstrap").fetch("records").fetch("badges").fetch("first_session").fetch("id"))
    assert_equal "First Session", badge.name
    assert_equal "Logged your first reading session.", badge.description
    assert badge.valid?
  end

  test "catalog replay and bootstrap share one manifest and lock in a coordinated operation" do
    write_snapshot
    context = DevelopmentReadingScenarioManifest.new(path: @manifest_path, lock_path: @lock_path)
    bootstrap = build_bootstrap(manifest: context)
    replay = OpenLibraryCatalogReplay.new(snapshot_path: @snapshot_path, manifest: context)
    combined = nil

    Rails.stub(:env, "development".inquiry) do
      context.with_exclusive_access do
        bootstrap.bootstrap_scenario
        combined = replay.replay_catalog
      end
    end

    assert_equal "complete", combined.fetch("bootstrap").fetch("status")
    assert_equal "complete", combined.fetch("catalog").fetch("status")
    assert_equal 31, combined.fetch("bootstrap").fetch("actual_counts").fetch("users")
    assert_equal 100, combined.fetch("catalog").fetch("actual_counts").fetch("books")
    assert_equal combined, JSON.parse(@manifest_path.read)
    assert_not_requested :any, /https?:/
  end

  test "a shared manifest rejects another thread while allowing same-thread coordination" do
    context = DevelopmentReadingScenarioManifest.new(path: @manifest_path, lock_path: @lock_path)

    Rails.stub(:env, "development".inquiry) do
      context.with_exclusive_access do
        assert_equal :nested_access, context.with_exclusive_access { :nested_access }
        error = Thread.new do
          context.with_exclusive_access { :unexpected_access }
        rescue DevelopmentReadingScenarioManifest::ManifestError => failure
          failure
        end.value
        assert_instance_of DevelopmentReadingScenarioManifest::ManifestError, error
        assert_includes error.message, "already running"
      end
    end
  end

  test "another process lock refuses bootstrap before database changes or manifest creation" do
    FileUtils.mkdir_p(@lock_path.dirname)
    File.open(@lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
      assert lock.flock(File::LOCK_EX | File::LOCK_NB)
      assert_no_difference [ "User.count", "Genre.count", "Badge.count" ] do
        assert_raises(DevelopmentReadingScenarioBootstrap::BootstrapError) { bootstrap_scenario }
      end
    end

    assert_not @manifest_path.exist?
    assert_not_requested :any, /https?:/
  end

  test "non-development bootstrap refuses before filesystem writes or HTTP requests" do
    [ "test", "production" ].each do |environment|
      Rails.stub(:env, environment.inquiry) do
        assert_raises(DevelopmentReadingScenarioBootstrap::BootstrapError) { @bootstrap.bootstrap_scenario }
      end
    end

    assert_empty @directory.children
    assert_not_requested :any, /https?:/
  end

  private

  def queue_adapter_for_test
    ActiveJob::QueueAdapters::TestAdapter.new
  end

  def build_bootstrap(password: @password, manifest: nil)
    DevelopmentReadingScenarioBootstrap.new(
      snapshot_path: @snapshot_path, manifest_path: @manifest_path,
      lock_path: @lock_path, password: password, manifest: manifest
    )
  end

  def write_snapshot
    stub_request(:get, "https://openlibrary.org/search.json")
      .with(query: hash_including(page: "1"))
      .to_return(status: 200, body: { docs: @docs }.to_json)
    Rails.stub(:env, "development".inquiry) do
      OpenLibraryCatalogCapture.new(
        snapshot_path: @snapshot_path, lock_path: @directory.join("capture.lock"), contact_email: "contact@example.test"
      ).capture_catalog
    end
    WebMock.reset!
  end

  def scenario_plan
    Rails.stub(:env, "development".inquiry) do
      catalog = OpenLibraryCatalogPreflight.new(snapshot_path: @snapshot_path).preflight_catalog
      DevelopmentReadingScenarioPlan.new(catalog: catalog).build_baseline
    end
  end

  def bootstrap_scenario
    Rails.stub(:env, "development".inquiry) { @bootstrap.bootstrap_scenario }
  end

  def user_records(manifest)
    manifest.fetch("bootstrap").fetch("records").fetch("users")
  end

  def bootstrap_ids(manifest)
    manifest.fetch("bootstrap").fetch("records").transform_values do |records|
      records.transform_values { |record| record.fetch("id") }
    end
  end

  def interrupt_after_first_account_commit
    original_rename = File.method(:rename)
    File.stub(:rename, ->(source, destination) {
      if Pathname.new(destination) == @manifest_path && User.exists?(email: "reader01@example.test")
        raise IOError, "Interrupted after first account commit"
      end
      original_rename.call(source, destination)
    }) do
      assert_raises(IOError) { bootstrap_scenario }
    end
  end

  def restore_shared_records(model, originals)
    model.where.not(id: originals.map { |attributes| attributes.fetch("id") }).find_each(&:destroy!)
    originals.each do |attributes|
      existing = model.find_by(id: attributes.fetch("id"))
      existing ? existing.update!(attributes.except("id")) : model.create!(attributes)
    end
  end
end
