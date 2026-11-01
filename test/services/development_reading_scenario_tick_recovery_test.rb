require "test_helper"
require_relative "../support/development_reading_scenario_tick_context"

class DevelopmentReadingScenarioTickRecoveryTest < ActiveSupport::TestCase
  include DevelopmentReadingScenarioTickContext

  test "a session committed before its checkpoint is reused without duplicate callback jobs" do
    initial = queue_count("BookProgressJob")
    interrupt_checkpoint_when { scenario_sessions.count > 300 }
    first = scenario_sessions.order(:id).last
    manifest = JSON.parse(@paths.fetch(:manifest_path).read)
    assert_nil tick_records(manifest, "reading_sessions").fetch("reading1").fetch("id")
    completed = advance
    assert_equal first.id, tick_ids(completed).fetch("reading_sessions").fetch("reading1")
    assert_equal initial + 3, queue_count("BookProgressJob")
    assert_equal 303, scenario_sessions.count
    assert_equal 82, scenario_posts.count
    assert_not_requested :any, /https?:/
  end

  test "a post committed before its checkpoint is reused without repeating its broadcast" do
    interrupt_checkpoint_when { scenario_posts.count > 80 }
    first = scenario_posts.order(:id).last
    stream = ClubDiscussionChannel.broadcasting_for(club("steady"))
    assert_equal 28, broadcasts(stream).length
    completed = advance
    assert_equal first.id, tick_ids(completed).fetch("club_messages").fetch("discussion1")
    assert_equal 28, broadcasts(stream).length
    assert_equal 82, scenario_posts.count
  end

  test "all five checkpointed events can resume before their final result is recorded" do
    interrupt_checkpoint_when do |contents|
      contents.dig("reading", "actual_counts", "reading_sessions") == 303 && contents.dig("ticks", "tick1", "actual_counts").nil?
    end
    saved = JSON.parse(@paths.fetch(:manifest_path).read)
    assert tick_records(saved, "reading_sessions").values.all? { |record| record.fetch("id") }
    assert tick_records(saved, "club_messages").values.all? { |record| record.fetch("id") }
    queue = enqueued_jobs.dup
    completed = nil
    assert_no_difference [ "ReadingSession.count", "ClubMessage.count" ] do
      completed = advance
    end
    assert_equal tick_ids(saved), tick_ids(completed)
    assert_equal({ "reading_sessions" => 303, "club_messages" => 82 }, completed.dig("ticks", "tick1", "scenario_counts"))
    assert_equal queue, enqueued_jobs
  end

  test "ambiguous committed session candidates are reported before any remaining tick writes" do
    interrupt_checkpoint_when { scenario_sessions.count > 300 }
    first = scenario_sessions.order(:id).last
    duplicate = ReadingSession.create!(first.attributes.except("id", "created_at", "updated_at"))
    assert_ambiguous_without_writes(first, duplicate)
  end

  test "reconciliation refuses complete database writes until every event ID is checkpointed" do
    interrupt_checkpoint_when { scenario_posts.count == 82 }
    saved = @paths.fetch(:manifest_path).read
    assert_nil tick_records(JSON.parse(saved), "club_messages").fetch("discussion2").fetch("id")
    error = assert_raises(DevelopmentReadingScenarioTick::TickError) do
      in_development { @tick.reconcile_tick(tick: "tick1") }
    end
    assert_includes error.message, "Resume tick1 with advance_scenario"
    assert_equal saved, @paths.fetch(:manifest_path).read
    completed = advance
    assert_equal({ "reading_sessions" => 303, "club_messages" => 82 }, completed.dig("ticks", "tick1", "scenario_counts"))
  end

  test "ambiguous committed post candidates are reported before any remaining tick writes" do
    interrupt_checkpoint_when { scenario_posts.count > 80 }
    first = scenario_posts.order(:id).last
    duplicate = ClubMessage.create!(first.attributes.except("id", "created_at", "updated_at"))
    assert_ambiguous_without_writes(first, duplicate)
  end

  test "edited or deleted known tick events are refused instead of overwritten or recreated" do
    manifest = advance
    session = ReadingSession.find(tick_ids(manifest).fetch("reading_sessions").fetch("reading3"))
    original = session.notes
    session.update!(notes: "A reader revised the private note")
    assert_no_difference [ "ReadingSession.count", "ClubMessage.count" ] do
      error = assert_raises(DevelopmentReadingScenarioTick::TickError) { advance }
      assert_includes error.message, session.id.to_s
      assert_includes error.message, "changed"
    end
    session.update!(notes: original)
    post_id = tick_ids(manifest).fetch("club_messages").fetch("discussion2")
    ClubMessage.find(post_id).destroy!
    assert_no_difference [ "ReadingSession.count", "ClubMessage.count" ] do
      error = assert_raises(DevelopmentReadingScenarioTick::TickError) { advance }
      assert_includes error.message, post_id.to_s
      assert_includes error.message, "missing"
    end
  end

  test "a matching event without saved tick intent is refused rather than adopted" do
    ReadingSession.create!(user: User.find_by!(email: "reader08@example.test"), book: club("steady").current_book,
      read_on: Date.new(2026, 10, 30), pages_read: 16,
      notes: "Synthetic journal. Follow-up reading: I revisited a passage and compared it with my earlier notes.")
    saved = @paths.fetch(:manifest_path).read
    assert_no_difference [ "ReadingSession.count", "ClubMessage.count" ] do
      error = assert_raises(DevelopmentReadingScenarioTick::TickError) { advance }
      assert_includes error.message, "Unrecorded"
    end
    assert_equal saved, @paths.fetch(:manifest_path).read
  end

  test "validation failure is checkpointed and resumes after its cause is resolved" do
    invalid = ReadingSession.new
    invalid.errors.add(:pages_read, "must be greater than 0")
    recorder = Object.new
    recorder.define_singleton_method(:record) { invalid }
    ReadingSessionRecorder.stub(:new, recorder) do
      assert_raises(DevelopmentReadingScenarioTick::TickError) { advance }
    end
    manifest = JSON.parse(@paths.fetch(:manifest_path).read)
    assert_equal "failed", tick_records(manifest, "reading_sessions").fetch("reading1").fetch("result")
    assert_equal 300, scenario_sessions.count
    completed = advance
    assert_equal 303, scenario_sessions.count
    assert tick_records(completed, "reading_sessions").values.none? { |record| record.key?("errors") }
  end

  private

  def scenario_sessions
    ReadingSession.where.not(user_id: @initial_users)
  end

  def scenario_posts
    ClubMessage.where(user_id: User.where.not(id: @initial_users).select(:id))
  end

  def interrupt_checkpoint_when(&condition)
    original = File.method(:rename)
    File.stub(:rename, ->(source, destination) {
      if Pathname.new(destination) == @paths.fetch(:manifest_path) && condition.call(JSON.parse(Pathname.new(source).read))
        raise IOError, "Interrupted after committed tick write"
      end
      original.call(source, destination)
    }) do
      assert_raises(IOError) { advance }
    end
  end

  def assert_ambiguous_without_writes(first, duplicate)
    saved = @paths.fetch(:manifest_path).read
    queue = enqueued_jobs.dup
    assert_no_difference [ "ReadingSession.count", "ClubMessage.count" ] do
      error = assert_raises(DevelopmentReadingScenarioTick::TickError) { advance }
      assert_includes error.message, "Ambiguous"
      assert_includes error.message, first.id.to_s
      assert_includes error.message, duplicate.id.to_s
    end
    assert_equal saved, @paths.fetch(:manifest_path).read
    assert_equal queue, enqueued_jobs
  end
end
