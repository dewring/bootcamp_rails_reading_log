require "test_helper"
require "tmpdir"

class DevelopmentReadingScenarioChallengesTest < ActiveSupport::TestCase
  uses_transaction "test_recovery_reuses_existing_enrollments_by_reader_and_challenge_after_a_failed_checkpoint"

  setup do
    @directory = Pathname.new(Dir.mktmpdir("booknook-challenges-"))
    @store = DevelopmentReadingScenarioManifest.new(path: @directory.join("manifest.json"), lock_path: @directory.join("scenario.lock"))
    @plan = DevelopmentReadingScenarioPlan.new.static_records
    @users = @plan.fetch("users").to_h do |entry|
      user = User.create!(entry.fetch("attributes").merge("password" => "synthetic-scenario-test-password"))
      [ entry.fetch("identity"), { "id" => user.id } ]
    end
    with_scenario do |manifest|
      manifest["bootstrap"] = { "records" => { "users" => @users } }
      @store.save_scenario
    end
  end

  teardown do
    FileUtils.remove_entry(@directory)
  end

  test "six challenges and forty enrollments create the three reader groups and preserve unrelated data" do
    existing_challenge = Challenge.create!(title: "Existing challenge", goal_type: "books_total", goal_value: 3, starts_at: 1.day.ago, ends_at: 30.days.from_now)
    existing_enrollment = UserChallenge.create!(user: users(:leika), challenge: existing_challenge)
    original = [ existing_challenge.attributes, existing_enrollment.attributes ]
    result = nil

    assert_difference "Challenge.count", 6 do
      assert_difference "UserChallenge.count", 40 do
        result = seed_challenges
      end
    end

    assert_equal "complete", result.dig("challenges", "status")
    assert_equal({ "challenges" => 6, "user_challenges" => 40 }, result.dig("challenges", "actual_counts"))
    counts = UserChallenge.where(user_id: @users.values.map { |record| record.fetch("id") }).group(:user_id).count
    readers = @users.except("admin").values.map { |record| counts.fetch(record.fetch("id"), 0) }
    assert_equal({ 3 => 10, 1 => 10, 0 => 10 }, readers.tally)
    assert_equal original, [ existing_challenge.reload.attributes, existing_enrollment.reload.attributes ]
    assert_not_requested :any, /https?:/
  end

  test "replay preserves ids timestamps and progress changed by application activity" do
    seed_challenges
    enrollment = UserChallenge.order(:id).last
    enrollment.update!(status: :in_progress, progress: 45)
    before = [ Challenge.order(:id).map(&:attributes), UserChallenge.order(:id).map(&:attributes) ]

    seed_challenges

    assert_equal before, [ Challenge.order(:id).map(&:attributes), UserChallenge.order(:id).map(&:attributes) ]
  end

  test "a unique challenge with matching title goal and dates is reused with its existing attributes" do
    planned = @plan.fetch("challenges").first
    identity = planned.fetch("identity")
    existing = Challenge.create!(planned.fetch("attributes").merge("created_at" => 1.year.ago))
    before = existing.attributes

    assert_difference "Challenge.count", 5 do
      result = seed_challenges.fetch("challenges")
      record = result.dig("records", "challenges", identity)
      assert_equal existing.id, record.fetch("id")
      assert_equal "reused", record.fetch("result")
      expected = @plan.fetch("user_challenges").count { |entry| entry.fetch("challenge") == identity }
      assert_equal expected, UserChallenge.where(challenge: existing).count
    end
    assert_equal before, existing.reload.attributes
  end

  test "two otherwise matching challenges are skipped as ambiguous" do
    planned = @plan.fetch("challenges").first
    attributes = planned.fetch("attributes")
    ids = Array.new(2) { Challenge.create!(attributes).id }

    result = seed_challenges.fetch("challenges")

    record = result.dig("records", "challenges", planned.fetch("identity"))
    assert_equal "skipped", record.fetch("result")
    assert_equal ids.sort, record.fetch("record_ids")
    assert_empty UserChallenge.where(challenge_id: ids)
  end

  test "a challenge title collision skips its enrollments and preserves unrelated imports on replay" do
    planned = @plan.fetch("challenges").first
    identity = planned.fetch("identity")
    existing = Challenge.create!(planned.fetch("attributes").merge("goal_value" => 99))
    before = existing.attributes
    skipped_count = @plan.fetch("user_challenges").count { |entry| entry.fetch("challenge") == identity }

    first = seed_challenges.fetch("challenges")
    challenge = first.dig("records", "challenges", identity)
    assert_equal "skipped", challenge.fetch("result")
    assert_equal "challenge_title_collision", challenge.fetch("reason")
    assert_equal [ existing.id ], challenge.fetch("record_ids")
    skipped = first.dig("records", "user_challenges").values.select { |row| row["result"] == "skipped" }
    assert_equal skipped_count, skipped.length
    assert skipped.all? { |row| row["challenge"] == identity && row["reason"] == "challenge_skipped" }
    assert_equal({ "challenges" => 5, "user_challenges" => 40 - skipped_count }, first.fetch("actual_counts"))
    assert_empty UserChallenge.where(challenge: existing)
    assert_equal before, existing.reload.attributes

    assert_no_difference [ "Challenge.count", "UserChallenge.count" ] do
      assert_equal first, seed_challenges.fetch("challenges")
    end
  end

  test "replay reuses an edited challenge by ID without overwriting its changes or enrollments" do
    first = seed_challenges.fetch("challenges")
    challenge = Challenge.order(:id).last
    challenge.update!(title: "A revised demo challenge", goal_value: 99)
    before = challenge.attributes
    enrollments = UserChallenge.where(challenge: challenge).order(:id).map(&:attributes)

    assert_no_difference [ "Challenge.count", "UserChallenge.count" ] do
      assert_equal first, seed_challenges.fetch("challenges")
    end

    assert_equal before, challenge.reload.attributes
    assert_equal enrollments, UserChallenge.where(challenge: challenge).order(:id).map(&:attributes)
  end

  test "replay skips a deleted challenge and its enrollments without changing unrelated rows" do
    first = seed_challenges.fetch("challenges")
    identity, record = first.dig("records", "challenges").first
    challenge = Challenge.find(record.fetch("id"))
    deleted_count = challenge.user_challenges.count
    challenge.destroy!
    before = [ Challenge.order(:id).map(&:attributes), UserChallenge.order(:id).map(&:attributes) ]

    result = seed_challenges.fetch("challenges")
    skipped = result.dig("records", "challenges", identity)
    assert_equal "skipped", skipped.fetch("result")
    assert_equal "recorded_challenge_missing", skipped.fetch("reason")
    assert_equal challenge.id, skipped.fetch("id")
    enrollments = result.dig("records", "user_challenges").values.select { |row| row.fetch("challenge") == identity }
    assert_equal deleted_count, enrollments.length
    assert enrollments.all? { |row| row["result"] == "skipped" && row["reason"] == "challenge_skipped" }
    assert_equal({ "challenges" => 5, "user_challenges" => 40 - deleted_count }, result.fetch("actual_counts"))
    assert_equal result, seed_challenges.fetch("challenges")
    assert_equal before, [ Challenge.order(:id).map(&:attributes), UserChallenge.order(:id).map(&:attributes) ]
  end

  test "replay reports a deleted enrollment without recreating it" do
    first = seed_challenges.fetch("challenges")
    enrollment = UserChallenge.order(:id).last
    identity, = first.dig("records", "user_challenges").find { |_, record| record["id"] == enrollment.id }
    enrollment.destroy!

    assert_no_difference [ "Challenge.count", "UserChallenge.count" ] do
      result = seed_challenges.fetch("challenges")
      skipped = result.dig("records", "user_challenges", identity)
      assert_equal "skipped", skipped.fetch("result")
      assert_equal "recorded_enrollment_missing", skipped.fetch("reason")
      assert_equal enrollment.id, skipped.fetch("id")
      assert_equal({ "challenges" => 6, "user_challenges" => 39 }, result.fetch("actual_counts"))
      assert_equal result, seed_challenges.fetch("challenges")
    end
  end

  test "replay skips a reassigned enrollment and preserves edits to an enrollment with the same reader and challenge" do
    first = seed_challenges.fetch("challenges")
    records = first.dig("records", "user_challenges")
    identity, recorded = records.first
    reassigned = UserChallenge.find(recorded.fetch("id"))
    reassigned.update!(user: users(:leika))
    edited = UserChallenge.find(records.values.last.fetch("id"))
    edited.update!(created_at: edited.created_at + 1.day, progress: 40)
    before = UserChallenge.order(:id).map(&:attributes)

    result = seed_challenges.fetch("challenges")

    skipped = result.dig("records", "user_challenges", identity)
    assert_equal "skipped", skipped.fetch("result")
    assert_equal "recorded_enrollment_identity_changed", skipped.fetch("reason")
    assert_equal reassigned.id, skipped.fetch("id")
    assert_equal({ "challenges" => 6, "user_challenges" => 39 }, result.fetch("actual_counts"))
    assert_equal before, UserChallenge.order(:id).map(&:attributes)
    assert_equal result, seed_challenges.fetch("challenges")
  end

  test "an invalid enrollment leaves other enrollments in place and can be retried" do
    factory = UserChallenge.method(:create!)
    created = 0
    fail_second = ->(attributes) {
      created += 1
      raise ActiveRecord::RecordInvalid, UserChallenge.new if created == 2

      factory.call(attributes)
    }

    result = UserChallenge.stub(:create!, fail_second) { seed_challenges }
    assert_equal 39, result.dig("challenges", "actual_counts", "user_challenges")
    assert_difference("UserChallenge.count", 1) { seed_challenges }
  end

  test "recovery reuses existing enrollments by reader and challenge after a failed checkpoint" do
    rename = File.method(:rename)
    File.stub(:rename, ->(source, destination) {
      if Pathname.new(destination) == @directory.join("manifest.json") && UserChallenge.count == 40
        raise IOError, "Interrupted after challenge commit"
      end
      rename.call(source, destination)
    }) do
      assert_raises(IOError) { seed_challenges }
    end
    enrollment = UserChallenge.order(:id).first
    enrollment.update!(created_at: enrollment.created_at + 1.day, status: :in_progress, progress: 45)
    before = [ Challenge.order(:id).map(&:attributes), UserChallenge.order(:id).map(&:attributes) ]

    result = seed_challenges

    assert_equal "complete", result.dig("challenges", "status")
    assert_includes result.dig("challenges", "records", "user_challenges").values.map { |record| record.fetch("id") }, enrollment.id
    assert_equal before, [ Challenge.order(:id).map(&:attributes), UserChallenge.order(:id).map(&:attributes) ]
  end

  private

  def with_scenario
    Rails.stub(:env, "development".inquiry) do
      @store.with_exclusive_access do
        manifest = @store.prepare_scenario(snapshot_id: "challenge-test")
        yield manifest
      end
    end
  end

  def seed_challenges
    with_scenario do |manifest|
      DevelopmentReadingScenarioChallenges.new(plan: @plan, manifest: manifest, scenario_manifest: @store).seed_challenges
    end
  end
end
