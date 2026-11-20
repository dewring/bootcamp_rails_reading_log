require "test_helper"
require "tmpdir"

class DevelopmentReadingScenarioTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @directory = Pathname.new(Dir.mktmpdir("reading-simulation-"))
    @path = @directory.join("manifest.json")
    @lock = @directory.join("demo.lock")
    @scenario = DevelopmentReadingScenario.new(manifest_path: @path, lock_path: @lock, password: "local-demo-password")
  end

  teardown { FileUtils.remove_entry(@directory) }

  test "each run reuses static data and adds current sessions, reviews, reactions and discussions" do
    first = simulate
    assert_equal "complete", first.fetch("status"), first["skipped"].inspect
    assert_equal 100, first.dig("static_counts", "books")
    assert_equal({ "reading_sessions" => 30, "reviews" => 30, "reactions" => 30, "club_messages" => 4 }, first.fetch("added"))
    ids = [ Book, BookEdition, User, Badge, Genre, BookGenre, BookClub, BookClubMembership, Challenge, UserChallenge ].to_h do |model|
      [ model, model.order(:id).ids ]
    end
    existing = [ Review, Reaction ].to_h { |model| [ model, model.order(:id).map(&:attributes) ] }
    travel 1.day do
      assert_difference({ "ReadingSession.count" => 30, "Review.count" => 30, "Reaction.count" => 30, "ClubMessage.count" => 4 }) do
        assert_equal first, simulate
      end
      assert_equal 30, ReadingSession.where(read_on: Date.current, user: User.where("email LIKE 'reader%@example.test'")).count
    end
    ids.each { |model, expected| assert_equal expected, model.order(:id).ids }
    existing.each do |model, rows|
      assert_equal rows, model.where(id: rows.pluck("id")).order(:id).map(&:attributes)
    end
    assert_not_includes first.to_json, "encrypted_password"
    assert_not_requested :any, /https?:/
  end

  test "unavailable accounts and disabled reactions leave independent activity usable" do
    real = User.create!(email: "reader07@example.test", nickname: "fixture_collision", first_name: "Existing", last_name: "Reader", password: "test-password")
    ReactionType.update_all(enabled: false)
    report = simulate
    assert_equal "partial", report.fetch("status")
    assert_equal "account_identity_collision", report.dig("skipped", "users/reader07")
    assert_equal 29, report.dig("added", "reading_sessions")
    assert_equal 29, report.dig("added", "reviews")
    assert_equal 0, report.dig("added", "reactions")
    assert_equal 3, report.dig("added", "club_messages")
    assert_empty real.reading_sessions
    assert_empty real.reviews
  end

  test "clubs reading the same book get different posts in each round and fresh posts on subsequent rounds" do
    simulate
    clubs = BookClub.where(id: JSON.parse(@path.read).fetch("simulation_clubs").values)
    book = clubs.first.current_book
    clubs.update_all(current_book_id: book.id)
    require "faker"
    Faker::Book.stub(:title, book.title) do
      3.times do
        previous_id = ClubMessage.maximum(:id)
        simulate
        posts = ClubMessage.where(book_club: clubs).where(id: (previous_id + 1)..)
        assert_equal 4, posts.pluck(:body).uniq.size
      end
    end
    clubs.each do |club|
      bodies = club.club_messages.order(id: :desc).limit(3).pluck(:body)
      assert_equal 3, bodies.uniq.size
    end
  end

  test "saturated review and reaction pairs leave sessions and discussions available" do
    assert_equal "complete", simulate.fetch("status")
    manifest = JSON.parse(@path.read)
    reader = User.find_by!(email: "reader01@example.test")
    books = manifest.dig("catalog", "records").values.map { |pair| pair.dig("book", "id") }
    (books - reader.reviews.pluck(:book_id)).each { |id| Review.create!(user: reader, book_id: id, rating: 4) }
    (books - reader.reactions.pluck(:book_id)).each { |id| Reaction.create!(user: reader, book_id: id, kind: "like") }

    result = simulate

    assert_equal({ "reading_sessions" => 30, "reviews" => 29, "reactions" => 29, "club_messages" => 4 }, result.fetch("added"))
    assert_includes result.fetch("skipped"), "reviews/#{reader.id}"
    assert_includes result.fetch("skipped"), "reactions/#{reader.id}"
  end

  test "a legacy manifest supplies the original club ids and reference date while new activity uses today" do
    simulate
    manifest = JSON.parse(@path.read)
    clubs = manifest.delete("simulation_clubs")
    manifest["as_of"] = "2026-10-30T12:00:00.000000Z"
    manifest["community"] = { "records" => { "book_clubs" => clubs.transform_values { |id| { "id" => id, "result" => "imported" } } } }
    @path.write(JSON.generate(manifest))
    assert_no_difference [ "BookClub.count", "BookClubMembership.count" ] do
      assert_difference("ReadingSession.count", 30) { assert_equal "complete", simulate.fetch("status") }
    end
    assert_equal manifest["as_of"], JSON.parse(@path.read).fetch("as_of")
    assert_equal 2, ClubMessage.where(book_club_id: clubs.fetch("steady")).count
  end

  test "an unsafe manifest and an overlapping run report why they stopped before writing" do
    File.open(@lock, "w") do |lock|
      lock.flock(File::LOCK_EX)
      assert_no_difference("Book.count") { assert_match(/already running/, simulate.fetch("reason")) }
    end
    @path.write("invalid json")
    assert_no_difference [ "User.count", "Book.count", "ReadingSession.count" ] do
      assert_match(/invalid JSON/, simulate.fetch("reason"))
    end
    assert_equal "invalid json", @path.read
  end

  test "production database preparation does not run the simulator even with opt-in" do
    Rails.env.stub(:production?, true) do
      DevelopmentReadingScenario.stub(:new, -> { flunk "db:prepare started the simulator" }) do
        assert load(Rails.root.join("db/seeds.rb"))
      end
    end
  end

  private

  def simulate
    Rails.env.stub(:development?, true) { @scenario.seed_scenario }
  end
end
