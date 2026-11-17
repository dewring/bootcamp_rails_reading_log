require "test_helper"
require "tmpdir"

class DevelopmentReadingScenarioChallengesTest < ActiveSupport::TestCase
  uses_transaction "test_committed_challenges_and_enrollments_recover_after_the_manifest_checkpoint_fails"

  setup do
    @directory = Pathname.new(Dir.mktmpdir("booknook-challenges-"))
    @store = DevelopmentReadingScenarioManifest.new(path: @directory.join("manifest.json"), lock_path: @directory.join("scenario.lock"))
    catalog = { "snapshot_id" => "challenge-test", "books" => Array.new(100) { |index| { "book_attributes" => { "ol_work_key" => "/works/OL#{300_000 + index}W" } } } }
    @plan = DevelopmentReadingScenarioPlan.new(catalog: catalog).build_baseline
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

  test "a deleted recorded enrollment is refused without recreating it" do
    seed_challenges
    UserChallenge.order(:id).last.destroy!

    assert_no_difference [ "Challenge.count", "UserChallenge.count" ] do
      assert_raises(DevelopmentReadingScenarioChallenges::ChallengeError) { seed_challenges }
    end
  end

  test "an enrollment failure rolls back the whole challenge phase and can be retried" do
    factory = UserChallenge.method(:create!)
    created = 0
    fail_second = ->(attributes) {
      created += 1
      raise ActiveRecord::RecordInvalid, UserChallenge.new if created == 2

      factory.call(attributes)
    }

    assert_no_difference [ "Challenge.count", "UserChallenge.count" ] do
      UserChallenge.stub(:create!, fail_second) do
        assert_raises(ActiveRecord::RecordInvalid) { seed_challenges }
      end
    end

    assert_equal "complete", seed_challenges.dig("challenges", "status")
  end

  test "committed challenges and enrollments recover after the manifest checkpoint fails" do
    rename = File.method(:rename)
    File.stub(:rename, ->(source, destination) {
      if Pathname.new(destination) == @directory.join("manifest.json") && UserChallenge.count == 40
        raise IOError, "Interrupted after challenge commit"
      end
      rename.call(source, destination)
    }) do
      assert_raises(IOError) { seed_challenges }
    end
    before = [ Challenge.order(:id).map(&:attributes), UserChallenge.order(:id).map(&:attributes) ]

    result = seed_challenges

    assert_equal "complete", result.dig("challenges", "status")
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
