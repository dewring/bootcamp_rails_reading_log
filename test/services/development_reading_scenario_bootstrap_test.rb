require "test_helper"
require "tmpdir"

class DevelopmentReadingScenarioBootstrapTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  uses_transaction "test_an_account_committed_before_its_manifest_update_resumes_only_with_its_original_planned_Devise_hash"

  setup do
    @initial_user_ids = User.pluck(:id)
    @directory = Pathname.new(Dir.mktmpdir("booknook-scenario-bootstrap-"))
    @manifest_path = @directory.join("state/reading_scenario.json")
    @lock_path = @directory.join("state/reading_scenario.lock")
    @password = "synthetic-scenario-test-password"
    @store = DevelopmentReadingScenarioManifest.new(path: @manifest_path, lock_path: @lock_path)
  end

  teardown do
    FileUtils.remove_entry(@directory)
  end

  test "bootstrap creates 30 readers and one admin while retaining all genre and badge types" do
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
    first = bootstrap_scenario
    before = User.order(:id).map(&:attributes)

    second = bootstrap_scenario(password: nil)

    assert_equal bootstrap_ids(first), bootstrap_ids(second)
    assert_equal first.dig("bootstrap", "actual_counts"), second.dig("bootstrap", "actual_counts")
    assert_equal before, User.order(:id).map(&:attributes)
    assert user_records(second).values.all? { |record| record.fetch("result") == "reused" }
  end


  test "an existing reader email is preserved while other accounts and lookup records are created" do
    collision = User.create!(
      first_name: "Existing", last_name: "Person", nickname: "existing_person",
      email: "reader01@example.test", password: @password, role: "user", account_status: "active"
    )
    before = collision.attributes

    assert_difference "User.count", 30 do
      record = user_records(bootstrap_scenario).fetch("reader01")
      assert_equal "skipped", record.fetch("result")
      assert_equal [ collision.id ], record.fetch("record_ids")
      assert_nil record.fetch("id")
    end
    assert_equal before, collision.reload.attributes
  end


  test "a final admin nickname collision never promotes the existing account" do
    collision = User.create!(
      first_name: "Existing", last_name: "Reader", nickname: "avery.morgan",
      email: "someone@example.test", password: @password, role: "user", account_status: "active"
    )

    assert_difference "User.count", 30 do
      record = user_records(bootstrap_scenario).fetch("admin")
      assert_equal "skipped", record.fetch("result")
      assert_equal [ collision.id ], record.fetch("record_ids")
    end
    assert_equal "user", collision.reload.role
  end


  test "matching public attributes and a matching password do not authorize takeover of an existing account" do
    attributes = scenario_plan.fetch("users").first.fetch("attributes")
    existing = User.create!(attributes.merge("password" => @password))
    before = existing.attributes

    record = user_records(bootstrap_scenario).fetch("reader01")

    assert_equal "account_identity_collision", record.fetch("reason")
    assert_nil record.fetch("id")
    assert_equal [ existing.id ], record.fetch("record_ids")
    assert_equal before, existing.reload.attributes
  end

  test "missing and invalid passwords leave the catalog usable and accounts can be created on retry" do
    [ nil, "x" ].each do |password|
      result = bootstrap_scenario(password: password)
      assert_equal 0, result.dig("bootstrap", "actual_counts", "users")
      assert_equal 5, result.dig("bootstrap", "actual_counts", "badges")
      assert_predicate user_records(result).fetch("reader01").fetch("reason"), :present?
    end
    assert_difference("User.count", 31) { bootstrap_scenario }
  end

  test "an account committed before its manifest update resumes only with its original planned Devise hash" do
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


  test "replay skips an uncheckpointed account whose credentials changed and resumes other accounts" do
    interrupt_after_first_account_commit
    user = User.find_by!(email: "reader01@example.test")
    user.update!(password: "a-different-synthetic-password")
    before = user.attributes

    assert_difference "User.count", 30 do
      record = user_records(bootstrap_scenario).fetch("reader01")
      assert_equal "account_identity_or_credentials_changed", record.fetch("reason")
      assert_equal [ user.id ], record.fetch("record_ids")
    end
    assert_equal before, user.reload.attributes
    assert User.exists?(email: "reader02@example.test")
  end

  test "a wrong password preserves the recovered account and leaves pending accounts retryable" do
    interrupt_after_first_account_commit
    assert_no_difference "User.count" do
      result = bootstrap_scenario(password: "another-local-test-password")
      assert_equal "reused", user_records(result).fetch("reader01").fetch("result")
      assert_match(/password differs/, user_records(result).fetch("reader02").fetch("reason"))
    end
    assert_difference("User.count", 30) { bootstrap_scenario }
  end

  test "a missing recorded credential skips only its account" do
    interrupt_after_first_account_commit
    manifest = JSON.parse(@manifest_path.read)
    user_records(manifest).fetch("reader01").fetch("expected_attributes").delete("encrypted_password")
    @manifest_path.write(JSON.pretty_generate(manifest))
    result = bootstrap_scenario
    assert_equal "recorded_credentials_missing", user_records(result).fetch("reader01").fetch("reason")
    assert_equal 30, result.dig("bootstrap", "actual_counts", "users")
  end

  test "a deleted recorded user is not silently recreated" do
    manifest = bootstrap_scenario
    id = user_records(manifest).fetch("reader30").fetch("id")
    User.find(id).destroy!

    assert_no_difference "User.count" do
      record = user_records(bootstrap_scenario).fetch("reader30")
      assert_equal "recorded_account_missing", record.fetch("reason")
      assert_equal "skipped", record.fetch("result")
      assert_equal id, record.fetch("id")
    end
  end

  test "a user edited after preflight is rechecked before its replay checkpoint without overwriting the edit" do
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
      record = user_records(bootstrap_scenario).fetch("reader01")
      assert_equal user.id, record.fetch("id")
      assert_equal "reused", record.fetch("result")
    end

    assert_equal "Developer edit", user.reload.first_name
  end

  test "a missing badge is recreated from the retained bootstrap defaults through normal validation" do
    missing = Badge.find_by!(badge_type: "first_session")
    missing.destroy!

    manifest = bootstrap_scenario

    badge = Badge.find(manifest.fetch("bootstrap").fetch("records").fetch("badges").fetch("first_session").fetch("id"))
    assert_equal "First Session", badge.name
    assert_equal "Logged your first reading session.", badge.description
    assert badge.valid?
  end

  test "a badge name already used by another type is reported while setup continues" do
    first = Badge.find_by!(badge_type: "first_session")
    first.destroy!
    existing = Badge.find_by!(badge_type: "week_streak")
    existing.update!(name: "First Session")
    before = existing.attributes

    assert_difference "User.count", 31 do
      result = bootstrap_scenario.fetch("bootstrap")
      record = result.dig("records", "badges", "first_session")
      assert_equal "skipped", record.fetch("result")
      assert_equal "badge_name_collision", record.fetch("reason")
      assert_equal [ existing.id ], record.fetch("record_ids")
      assert_equal 4, result.dig("actual_counts", "badges")
    end
    assert_not Badge.exists?(badge_type: "first_session")
    assert_equal before, existing.reload.attributes
  end

  test "badge replay preserves edits and skips deleted types until a replacement exists" do
    bootstrap_scenario
    missing = Badge.find_by!(badge_type: "first_session")
    missing.destroy!
    edited = Badge.find_by!(badge_type: "week_streak")
    edited.update!(description: "Updated catalog description")
    before = edited.attributes

    assert_no_difference "Badge.count" do
      result = bootstrap_scenario.fetch("bootstrap")
      record = result.dig("records", "badges", "first_session")
      assert_equal "recorded_badge_missing", record.fetch("reason")
      assert_equal missing.id, record.fetch("id")
      assert_equal 4, result.dig("actual_counts", "badges")
    end
    assert_equal before, edited.reload.attributes

    replacement = Badge.create!(badge_type: "first_session", name: "First Reading", description: "Awarded for the first log.")
    result = bootstrap_scenario.fetch("bootstrap")
    record = result.dig("records", "badges", "first_session")
    assert_equal replacement.id, record.fetch("id")
    assert_equal "reused", record.fetch("result")
    assert_nil record["reason"]
    assert_equal 5, result.dig("actual_counts", "badges")
  end

  test "an invalid badge is reported while users import and the badge can be retried" do
    Badge.find_by!(badge_type: "first_session").destroy!
    invalid = Badge.new(badge_type: "first_session")
    result = Badge.stub(:new, invalid) { bootstrap_scenario }
    assert_match(/Name/, result.dig("bootstrap", "records", "badges", "first_session", "reason"))
    assert_equal 31, result.dig("bootstrap", "actual_counts", "users")
    assert_difference("Badge.count", 1) { bootstrap_scenario }
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
        assert_raises(DevelopmentReadingScenarioManifest::ManifestError) { bootstrap_scenario }
      end
    end

    assert_not @manifest_path.exist?
    assert_not_requested :any, /https?:/
  end

  test "non-development bootstrap refuses before filesystem writes or HTTP requests" do
    [ "test", "production" ].each do |environment|
      Rails.stub(:env, environment.inquiry) do
        assert_raises(DevelopmentReadingScenarioManifest::ManifestError) { import_bootstrap }
      end
    end

    assert_empty @directory.children
    assert_not_requested :any, /https?:/
  end

  private

  def queue_adapter_for_test
    ActiveJob::QueueAdapters::TestAdapter.new
  end

  def scenario_plan
    DevelopmentReadingScenarioPlan.new.static_records
  end

  def bootstrap_scenario(password: @password)
    Rails.stub(:env, "development".inquiry) { import_bootstrap(password: password) }
  end

  def import_bootstrap(password: @password)
    @store.with_exclusive_access do
      manifest = @store.prepare_scenario(snapshot_id: "bootstrap-test")
      DevelopmentReadingScenarioBootstrap.new(plan: scenario_plan, manifest: manifest, scenario_manifest: @store, password: password).bootstrap_scenario
    end
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
end
