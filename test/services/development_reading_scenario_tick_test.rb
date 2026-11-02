require "test_helper"
require_relative "../support/development_reading_scenario_tick_context"

class DevelopmentReadingScenarioTickTest < ActiveSupport::TestCase
  include DevelopmentReadingScenarioTickContext

  test "tick1 adds exactly three dated sessions and two top-level posts with normal callbacks" do
    jobs = [ "BookProgressJob", "BadgeAwardJob", "ChallengeProgressJob", "BookClubLeaderboardJob" ].to_h { |name| [ name, queue_count(name) ] }
    result = nil
    assert_difference "ReadingSession.count", 3 do
      assert_difference "ClubMessage.count", 2 do
        result = advance
      end
    end
    tick = result.fetch("ticks").fetch("tick1")
    assert_equal({ "reading_sessions" => 3, "club_messages" => 2 }, tick.fetch("actual_counts"))
    assert_equal({ "reading_sessions" => 300, "club_messages" => 80 }, tick.fetch("baseline_counts"))
    assert_equal({ "reading_sessions" => 303, "club_messages" => 82 }, tick.fetch("scenario_counts"))
    assert_equal "complete", tick.fetch("status")
    assert_not tick.key?("callback_work")
    jobs.each { |name, count| assert_equal count + 3, queue_count(name) }
    sessions = ReadingSession.where(id: tick_ids(result).fetch("reading_sessions").values)
    assert_equal [ Date.new(2026, 10, 30) ], sessions.distinct.pluck(:read_on)
    assert_equal [ 16, 17, 18 ], sessions.order(:pages_read).pluck(:pages_read)
    assert_equal 28, broadcasts(ClubDiscussionChannel.broadcasting_for(club("steady"))).length
    assert_equal 28, broadcasts(ClubDiscussionChannel.broadcasting_for(club("lapsed"))).length
    assert_equal 26, broadcasts(ClubDiscussionChannel.broadcasting_for(club("recent"))).length
    assert_equal 0, club("quiet").club_messages.count
    posts = ClubMessage.where(id: tick_ids(result).fetch("club_messages").values)
    assert posts.all? { |post| post.parent_id.nil? && !post.body.include?("tick1") && !post.body.include?("@example.test") && !post.body.include?("/works/") }
    assert_not_requested :any, /https?:/
  end

  test "repeating a fully saved tick changes no rows jobs broadcasts or manifest contents" do
    first = advance
    saved = @paths.fetch(:manifest_path).read
    queue = enqueued_jobs.dup
    stream = ClubDiscussionChannel.broadcasting_for(club("steady"))
    before_broadcasts = broadcasts(stream).dup
    result = nil
    assert_no_difference [ "ReadingSession.count", "ClubMessage.count", "UserBook.count" ] do
      result = advance
    end
    assert_equal first, result
    assert_equal saved, @paths.fetch(:manifest_path).read
    assert_equal queue, enqueued_jobs
    assert_equal before_broadcasts, broadcasts(stream)
  end

  test "baseline replay preserves the tick and keeps the 10 plus 15 page example unchanged" do
    first = advance
    replayed = in_development { @seed.seed_baseline }
    assert_equal tick_ids(first), tick_ids(replayed)
    assert_equal 303, replayed.dig("baseline", "actual_counts", "reading_sessions")
    assert_equal 82, replayed.dig("baseline", "actual_counts", "club_messages")
    assert_equal 300, replayed.dig("baseline", "expected_counts", "reading_sessions")
    reader = User.find_by!(email: "reader07@example.test")
    example = club("steady")
    assert_equal 25, reader.reading_sessions.where(book_id: example.current_book_id).sum(:pages_read)
    assert_equal 15, example.leaderboard.find { |user| user.id == reader.id }.furthest_page_read
    assert_equal 16, example.leaderboard.find { |user| user.email == "reader08@example.test" }.furthest_page_read
    assert_not_requested :any, /https?:/
  end

  test "a completed tick remains unchanged before and after its background jobs perform" do
    advance
    before_jobs = advance
    assert_equal "complete", before_jobs.dig("ticks", "tick1", "status")
    assert_not before_jobs.dig("ticks", "tick1").key?("callback_work")
    assert_not_empty enqueued_jobs
    5.times do
      break if enqueued_jobs.empty?

      perform_enqueued_jobs
    end
    assert_empty enqueued_jobs
    after_jobs = advance
    assert_equal "complete", after_jobs.dig("ticks", "tick1", "status")
    assert_equal({ "reading_sessions" => 303, "club_messages" => 82 }, after_jobs.dig("ticks", "tick1", "scenario_counts"))
  end

  test "unsupported names non-development and overlapping runs are refused before writes" do
    saved = @paths.fetch(:manifest_path).read
    queue = enqueued_jobs.dup
    assert_no_difference [ "ReadingSession.count", "ClubMessage.count" ] do
      in_development do
        [ nil, "tick2" ].each do |name|
          assert_raises(DevelopmentReadingScenarioTick::TickError) { @tick.advance_scenario(tick: name) }
        end
      end
      Rails.stub(:env, "production".inquiry) do
        assert_raises(DevelopmentReadingScenarioTick::TickError) { @tick.advance_scenario(tick: "tick1") }
      end
      File.open(@paths.fetch(:lock_path), File::RDWR) do |lock|
        lock.flock(File::LOCK_EX | File::LOCK_NB)
        error = assert_raises(DevelopmentReadingScenarioTick::TickError) { advance }
        assert_includes error.message, "already running"
      end
    end
    assert_equal saved, @paths.fetch(:manifest_path).read
    assert_equal queue, enqueued_jobs
    assert_not_requested :any, /https?:/
  end

  test "a changed baseline review stops the tick before intent or activity is saved" do
    review_id = @baseline.dig("community", "records", "reviews").values.last.fetch("id")
    Review.find(review_id).update!(body: "A reader revised the review")
    saved = @paths.fetch(:manifest_path).read
    assert_no_difference [ "ReadingSession.count", "ClubMessage.count" ] do
      error = assert_raises(DevelopmentReadingScenarioTick::TickError) { advance }
      assert_includes error.message, review_id.to_s
    end
    assert_equal saved, @paths.fetch(:manifest_path).read
  end
end
