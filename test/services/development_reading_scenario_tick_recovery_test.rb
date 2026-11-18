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

  test "an unavailable edition is omitted from a tick session and the committed session can be recovered" do
    key = club("steady").current_book.ol_work_key
    edition = BookEdition.create!(book: books(:refactoring), ol_edition_key: "/books/OL185000M")
    path = @paths.fetch(:manifest_path)
    manifest = JSON.parse(path.read)
    manifest.dig("catalog", "records", key)["edition"] = {
      "id" => edition.id, "expected_attributes" => { "ol_edition_key" => edition.ol_edition_key }
    }
    path.write(JSON.pretty_generate(manifest))

    interrupt_checkpoint_when { scenario_sessions.count > 300 }
    committed = scenario_sessions.order(:id).last
    assert_nil committed.book_edition_id
    pending = tick_records(JSON.parse(path.read), "reading_sessions").fetch("reading1")
    assert_nil pending.fetch("expected_attributes").fetch("book_edition_id")

    completed = advance

    assert_equal committed.id, tick_ids(completed).fetch("reading_sessions").fetch("reading1")
    assert_equal 303, scenario_sessions.count
    assert_equal books(:refactoring).id, edition.reload.book_id
  end

  test "an interrupted named batch resumes on a later date without adopting the previous batch" do
    travel_to Time.zone.local(2026, 11, 16, 12) do
      first = in_development { @tick.advance_scenario(tick: "demo1") }
      first_ids = first.dig("ticks", "demo1", "reading_sessions").values.map { |record| record.fetch("id") }
      interrupt_checkpoint_when(tick: "demo2") { scenario_sessions.count > 303 }
      committed = scenario_sessions.order(:id).last
      assert_not_includes first_ids, committed.id
      travel 1.day

      completed = in_development { @tick.advance_scenario(tick: "demo2") }

      assert_equal committed.id, completed.dig("ticks", "demo2", "reading_sessions", "reading1", "id")
      assert_equal 306, scenario_sessions.count
      assert_equal 84, scenario_posts.count
      ids = completed.dig("ticks", "demo2", "reading_sessions").values.map { |record| record.fetch("id") }
      assert_equal [ Date.new(2026, 11, 16) ], ReadingSession.where(id: ids).distinct.pluck(:read_on)
      assert_equal first.fetch("ticks").fetch("demo1"), completed.fetch("ticks").fetch("demo1")
    end
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

  test "ambiguous committed sessions are skipped while other tick records are imported" do
    interrupt_checkpoint_when { scenario_sessions.count > 300 }
    first = scenario_sessions.order(:id).last
    duplicate = ReadingSession.create!(first.attributes.except("id", "created_at", "updated_at"))
    assert_ambiguous_tick_skipped(first, duplicate)
  end

  test "advancing again recovers the last committed post and finalizes the tick without another command" do
    interrupt_checkpoint_when { scenario_posts.count == 82 }
    saved = @paths.fetch(:manifest_path).read
    assert_nil tick_records(JSON.parse(saved), "club_messages").fetch("discussion2").fetch("id")
    post = scenario_posts.order(:id).last
    queued = enqueued_jobs.dup
    completed = nil
    assert_no_difference [ "ReadingSession.count", "ClubMessage.count" ] do
      completed = advance
    end
    assert_equal post.id, tick_records(completed, "club_messages").fetch("discussion2").fetch("id")
    assert_equal "complete", completed.dig("ticks", "tick1", "status")
    assert_equal queued, enqueued_jobs
    assert_equal({ "reading_sessions" => 303, "club_messages" => 82 }, completed.dig("ticks", "tick1", "scenario_counts"))
  end

  test "ambiguous committed posts are skipped while other tick records are imported" do
    interrupt_checkpoint_when { scenario_posts.count > 80 }
    first = scenario_posts.order(:id).last
    duplicate = ClubMessage.create!(first.attributes.except("id", "created_at", "updated_at"))
    assert_ambiguous_tick_skipped(first, duplicate)
  end


  test "an edited tick session is preserved and a deleted tick message is skipped" do
    manifest = advance
    session = ReadingSession.find(tick_ids(manifest).fetch("reading_sessions").fetch("reading3"))
    session.update!(notes: "A reader revised the private note")
    post_id = tick_ids(manifest).fetch("club_messages").fetch("discussion2")
    ClubMessage.find(post_id).destroy!
    assert_no_difference [ "ReadingSession.count", "ClubMessage.count" ] do
      replayed = advance
      skipped = tick_records(replayed, "club_messages").fetch("discussion2")
      assert_equal "recorded_community_row_missing", skipped.fetch("reason")
      assert_equal post_id, skipped.fetch("id")
      assert_equal 1, replayed.dig("ticks", "tick1", "actual_counts", "club_messages")
    end
    assert_equal "A reader revised the private note", session.reload.notes
  end


  test "an exact existing tick session is reused while unrelated activity continues" do
    existing = ReadingSession.create!(user: User.find_by!(email: "reader08@example.test"), book: club("steady").current_book,
      read_on: Date.new(2026, 10, 30), pages_read: 16,
      notes: "Synthetic journal. Follow-up reading: I revisited a passage and compared it with my earlier notes.")
    assert_difference({ "ReadingSession.count" => 2, "ClubMessage.count" => 2 }) do
      assert_equal existing.id, tick_ids(advance).fetch("reading_sessions").fetch("reading1")
    end
  end

  test "validation failure is checkpointed and resumes after its cause is resolved" do
    invalid = ReadingSession.new
    invalid.errors.add(:pages_read, "must be greater than 0")
    recorder = Object.new
    recorder.define_singleton_method(:record) { invalid }
    ReadingSessionRecorder.stub(:new, recorder) do
      error = assert_raises(ActiveRecord::RecordInvalid) { advance }
      assert_same invalid, error.record
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

  def interrupt_checkpoint_when(tick: "tick1", &condition)
    original = File.method(:rename)
    File.stub(:rename, ->(source, destination) {
      if Pathname.new(destination) == @paths.fetch(:manifest_path) && condition.call(JSON.parse(Pathname.new(source).read))
        raise IOError, "Interrupted after committed tick write"
      end
      original.call(source, destination)
    }) do
      assert_raises(IOError) { in_development { @tick.advance_scenario(tick: tick) } }
    end
  end

  def assert_ambiguous_tick_skipped(first, duplicate)
    group = first.is_a?(ReadingSession) ? "reading_sessions" : "club_messages"
    completed = advance
    reason = group == "reading_sessions" ? "ambiguous_reading_payload" : "ambiguous_community_identity"
    conflict = tick_records(completed, group).values.find { |row| row["reason"] == reason }
    assert_equal [ first.id, duplicate.id ].sort, conflict.fetch("record_ids")
    assert_equal "complete", completed.dig("ticks", "tick1", "status")
    assert first.class.exists?(first.id)
    assert duplicate.class.exists?(duplicate.id)
  end
end
