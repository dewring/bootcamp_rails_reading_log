require "test_helper"
require "tmpdir"
require_relative "../support/development_reading_scenario_setup"

class DevelopmentReadingScenarioCommunityTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include DevelopmentReadingScenarioSetup
  include ActionCable::TestHelper
  self.use_transactional_tests = false

  setup do
    @initial_user_ids = User.pluck(:id)
    @initial_book_ids = Book.pluck(:id)
    @initial_club_ids = BookClub.pluck(:id)
    @initial_genres = Genre.all.map(&:attributes)
    @initial_badges = Badge.all.map(&:attributes)
    @directory = Pathname.new(Dir.mktmpdir("booknook-community-"))
    @paths = { snapshot_path: @directory.join("catalog.json"), manifest_path: @directory.join("manifest.json"), lock_path: @directory.join("scenario.lock") }
    @community = DevelopmentReadingScenarioCommunity.new(**@paths)
    docs = Array.new(100) do |index|
      { "key" => "/works/OL#{195_000 + index}W", "title" => "Community source #{index}", "author_name" => [ "Source Author" ], "number_of_pages_median" => 1000 }
    end
    stub_request(:get, "https://openlibrary.org/search.json").with(query: hash_including(page: "1"))
      .to_return(status: 200, body: { docs: docs }.to_json)
    in_development do
      OpenLibraryCatalogCapture.new(snapshot_path: @paths.fetch(:snapshot_path), lock_path: @directory.join("capture.lock"), contact_email: "contact@example.test").capture_catalog
      prepare_scenario_data do |manifest|
        DevelopmentReadingScenarioBootstrap.new(**@paths, manifest: manifest, password: "synthetic-scenario-test-password").bootstrap_scenario
        OpenLibraryCatalogReplay.new(**@paths, manifest: manifest).replay_catalog
        DevelopmentReadingScenarioActivity.new(**@paths, manifest: manifest).replay_reading
      end
    end
    WebMock.reset!
  end

  teardown do
    BookClub.where.not(id: @initial_club_ids).find_each(&:destroy!)
    actors = User.where.not(id: @initial_user_ids).pluck(:id)
    # Cleanup should not enqueue progress, badge, and challenge jobs for discarded records.
    ReadingSession.where(user_id: actors).delete_all
    UserBook.where(user_id: actors).delete_all
    User.where(id: actors).find_each(&:destroy!)
    Book.where.not(id: @initial_book_ids).find_each(&:destroy!)
    restore_shared_records(Genre, @initial_genres)
    restore_shared_records(Badge, @initial_badges)
    FileUtils.remove_entry(@directory)
  end

  test "replay saves exact community counts with club owners normal broadcasts and unchanged page semantics" do
    original = BookClub.where(id: @initial_club_ids).order(:id).map(&:attributes)
    queued = enqueued_jobs.length
    manifest = replay
    assert_equal "saved", manifest.dig("community", "status")
    assert_equal({ "book_clubs" => 4, "book_club_memberships" => 24, "club_messages" => 80, "reviews" => 20, "club_messages_with_ticks" => 80 }, manifest.dig("community", "actual_counts"))
    assert_equal queued + 24, enqueued_jobs.length
    records(manifest, "book_clubs").each do |identity, record|
      club = BookClub.find(record.fetch("id"))
      assert_equal 6, club.book_club_memberships_count
      assert_equal club.book_club_memberships.count, club.book_club_memberships_count
      assert_equal [ record.fetch("owner_id") ], club.book_club_memberships.where(role: "owner").pluck(:user_id)
      expected = { "steady" => 27, "lapsed" => 27, "recent" => 26, "quiet" => 0 }.fetch(identity)
      assert_equal expected, club.club_messages.top_level.count
      assert_equal expected, broadcasts(ClubDiscussionChannel.broadcasting_for(club)).length
      assert_equal identity != "quiet", club.current_book_id.present?
    end
    club = BookClub.find(records(manifest, "book_clubs").fetch("steady").fetch("id"))
    reader = User.find_by!(email: "reader07@example.test")
    assert_equal 25, reader.reading_sessions.where(book_id: club.current_book_id).sum(:pages_read)
    assert_equal 15, club.leaderboard.find { |user| user.id == reader.id }.furthest_page_read
    messages = ClubMessage.where(id: records(manifest, "club_messages").values.map { |record| record.fetch("id") })
    assert messages.all? { |message| message.parent_id.nil? && message.body.start_with?("Synthetic discussion.") && message.body.include?("café") }
    assert_operator messages.maximum(Arel.sql("char_length(body)")), :>, 500
    assert_equal original, BookClub.where(id: @initial_club_ids).order(:id).map(&:attributes)
    assert_not_requested :any, /https?:/
  end

  test "replaying saved community data preserves IDs and does not repeat broadcasts or jobs" do
    first = replay
    jobs = enqueued_jobs.length
    clubs = records(first, "book_clubs").values.map { |record| BookClub.find(record.fetch("id")) }
    broadcast_counts = clubs.map { |club| broadcasts(ClubDiscussionChannel.broadcasting_for(club)).length }
    second = nil
    assert_no_difference [ "BookClub.count", "BookClubMembership.count", "ClubMessage.count", "Review.count" ] do
      second = replay
    end
    assert_equal community_ids(first), community_ids(second)
    assert_equal first.dig("community", "actual_counts"), second.dig("community", "actual_counts")
    assert_equal jobs, enqueued_jobs.length
    assert_equal broadcast_counts, clubs.map { |club| broadcasts(ClubDiscussionChannel.broadcasting_for(club)).length }
  end

  test "an existing club name is refused without taking over the club or writing memberships" do
    existing = BookClub.create!(name: "Reading Scenario Steady Readers")
    before = existing.attributes
    assert_no_difference [ "BookClub.count", "BookClubMembership.count", "ClubMessage.count", "Review.count" ] do
      error = assert_raises(DevelopmentReadingScenarioCommunity::CommunityError) { replay }
      assert_includes error.message, existing.id.to_s
      assert_includes error.message, "no automatic takeover"
    end
    assert_equal before, existing.reload.attributes
  end

  test "a club and owner committed before checkpoint resume together without duplicate owners" do
    interrupt_checkpoint_when { BookClub.where.not(id: @initial_club_ids).exists? }
    club = BookClub.where.not(id: @initial_club_ids).sole
    owner = club.book_club_memberships.sole
    manifest = JSON.parse(@paths.fetch(:manifest_path).read)
    assert_nil records(manifest, "book_clubs").fetch("steady").fetch("id")
    completed = replay
    assert_equal club.id, records(completed, "book_clubs").fetch("steady").fetch("id")
    assert_equal owner.id, records(completed, "book_club_memberships").fetch("steady/reader07").fetch("id")
    assert_equal 1, club.book_club_memberships.where(role: "owner").count
  end

  test "a message committed before checkpoint resumes without repeating its broadcast" do
    interrupt_checkpoint_when { ClubMessage.where(user_id: scenario_user_ids).exists? }
    message = ClubMessage.where(user_id: scenario_user_ids).sole
    stream = ClubDiscussionChannel.broadcasting_for(message.book_club)
    assert_equal 1, broadcasts(stream).length
    completed = replay
    assert_equal message.id, records(completed, "club_messages").fetch("steady/reflection01").fetch("id")
    assert_equal 27, broadcasts(stream).length
  end

  test "ambiguous committed messages stop replay and report both candidate IDs" do
    interrupt_checkpoint_when { ClubMessage.where(user_id: scenario_user_ids).exists? }
    first = ClubMessage.where(user_id: scenario_user_ids).sole
    duplicate = ClubMessage.create!(first.attributes.except("id", "created_at", "updated_at"))
    assert_no_difference [ "BookClub.count", "BookClubMembership.count", "ClubMessage.count", "Review.count" ] do
      error = assert_raises(DevelopmentReadingScenarioCommunity::CommunityError) { replay }
      assert_includes error.message, "Ambiguous"
      assert_includes error.message, first.id.to_s
      assert_includes error.message, duplicate.id.to_s
    end
  end

  test "a review committed before checkpoint resumes with the original ID" do
    interrupt_checkpoint_when { Review.where(user_id: scenario_user_ids).exists? }
    review = Review.where(user_id: scenario_user_ids).sole
    completed = replay
    assert_equal review.id, records(completed, "reviews").values.first.fetch("id")
    assert_equal 20, Review.where(user_id: scenario_user_ids).count
  end

  test "an unrecorded member in a scenario club stops replay without removing the membership" do
    manifest = replay
    club = BookClub.find(records(manifest, "book_clubs").fetch("steady").fetch("id"))
    outsider = User.find(@initial_user_ids.first)
    membership = club.book_club_memberships.create!(user: outsider, role: "member")
    assert_no_difference [ "BookClubMembership.count", "ClubMessage.count", "Review.count" ] do
      error = assert_raises(DevelopmentReadingScenarioCommunity::CommunityError) { replay }
      assert_includes error.message, membership.id.to_s
      assert_includes error.message, "Unrecorded"
    end
    assert BookClubMembership.exists?(membership.id)
  end

  test "baseline replay preserves the two additional posts recorded by a tick" do
    manifest = replay
    club = BookClub.find(records(manifest, "book_clubs").fetch("steady").fetch("id"))
    owner = User.find(records(manifest, "book_clubs").fetch("steady").fetch("owner_id"))
    posts = Array.new(2) { |index| club.club_messages.create!(user: owner, body: "Synthetic follow-up discussion #{index + 1}.") }
    manifest["ticks"] = { "first_tick" => { "club_messages" => posts.each_with_index.to_h do |post, index|
      [ "post#{index + 1}", { "id" => post.id, "expected_attributes" => JSON.parse(post.attributes.except("id", "updated_at").to_json) } ]
    end } }
    @paths.fetch(:manifest_path).write(JSON.generate(manifest))
    result = nil
    assert_no_difference [ "ClubMessage.count", "Review.count" ] do
      result = replay
    end
    assert_equal 82, result.dig("community", "actual_counts", "club_messages_with_ticks")
    assert_equal manifest.fetch("ticks"), result.fetch("ticks")
    assert_equal 29, broadcasts(ClubDiscussionChannel.broadcasting_for(club)).length
  end

  test "edited reviews and deleted messages are refused without overwriting or recreating them" do
    manifest = replay
    review = Review.find(records(manifest, "reviews").values.last.fetch("id"))
    review.update!(body: "Reader edited this review")
    assert_no_difference [ "ClubMessage.count", "Review.count" ] do
      error = assert_raises(DevelopmentReadingScenarioCommunity::CommunityError) { replay }
      assert_includes error.message, "changed"
      assert_includes error.message, review.id.to_s
    end
    review.update!(body: records(manifest, "reviews").values.last.fetch("expected_attributes").fetch("body"))
    message = ClubMessage.find(records(manifest, "club_messages").values.last.fetch("id"))
    message.destroy!
    assert_no_difference [ "ClubMessage.count", "Review.count" ] do
      error = assert_raises(DevelopmentReadingScenarioCommunity::CommunityError) { replay }
      assert_includes error.message, "missing"
      assert_includes error.message, message.id.to_s
    end
  end

  test "a failed message save preserves the invalid model and checkpoints the failure for retry" do
    invalid = ClubMessage.new
    ClubMessage.stub(:new, invalid) do
      error = assert_raises(ActiveRecord::RecordInvalid) { replay }
      assert_same invalid, error.record
    end
    manifest = JSON.parse(@paths.fetch(:manifest_path).read)
    failed = records(manifest, "club_messages").values.first
    assert_equal "failed", failed.fetch("result")
    assert_equal invalid.errors.full_messages, failed.fetch("errors")

    completed = replay
    assert_equal 80, completed.dig("community", "actual_counts", "club_messages")
    assert records(completed, "club_messages").values.none? { |record| record.key?("errors") }
  end

  test "non-development replay refuses before community writes" do
    assert_no_difference [ "BookClub.count", "BookClubMembership.count", "ClubMessage.count", "Review.count" ] do
      assert_raises(DevelopmentReadingScenarioManifest::ManifestError) { @community.replay_community }
    end
  end

  private

  def queue_adapter_for_test
    ActiveJob::QueueAdapters::TestAdapter.new
  end

  def in_development(&block)
    Rails.stub(:env, "development".inquiry, &block)
  end

  def replay
    in_development { @community.replay_community }
  end

  def records(manifest, group)
    manifest.fetch("community").fetch("records").fetch(group)
  end

  def community_ids(manifest)
    manifest.fetch("community").fetch("records").transform_values { |entries| entries.transform_values { |record| record.fetch("id") } }
  end

  def scenario_user_ids
    User.where.not(id: @initial_user_ids).pluck(:id)
  end

  def interrupt_checkpoint_when(&condition)
    original = File.method(:rename)
    File.stub(:rename, ->(source, destination) {
      raise IOError, "Interrupted after commit" if Pathname.new(destination) == @paths.fetch(:manifest_path) && condition.call

      original.call(source, destination)
    }) do
      assert_raises(IOError) { replay }
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
