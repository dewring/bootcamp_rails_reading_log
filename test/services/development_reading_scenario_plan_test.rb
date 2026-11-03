require "test_helper"

class DevelopmentReadingScenarioPlanTest < ActiveSupport::TestCase
  setup do
    @as_of = Time.zone.local(2026, 10, 30, 12)
    @catalog = {
      "snapshot_id" => "captured-test-snapshot",
      "books" => Array.new(100) do |index|
        {
          "book_attributes" => { "ol_work_key" => "/works/OL#{154_000 + index}W" },
          "edition_attributes" => index < 2 ? { "ol_edition_key" => "/books/OL#{154_000 + index}M" } : nil
        }
      end
    }
    @builder = DevelopmentReadingScenarioPlan.new(catalog: @catalog, as_of: @as_of)
  end

  test "baseline planning produces the exact inventory without changing database rows or making HTTP requests" do
    plan = nil

    assert_no_difference [ "User.count", "Book.count", "UserBook.count", "ReadingSession.count", "BookClub.count", "ClubMessage.count", "Review.count" ] do
      plan = build_baseline
    end

    assert_equal({
      "books" => 100, "book_editions" => 2, "users" => 31, "user_books" => 150,
      "reading_sessions" => 300, "book_clubs" => 4, "book_club_memberships" => 24,
      "club_messages" => 80, "reviews" => 20
    }, plan.fetch("counts"))
    assert_equal Genre::GENRES, plan.fetch("genres").map { |genre| genre.fetch("name") }
    assert_equal Badge.badge_types.keys.sort, plan.fetch("badges").map { |badge| badge.fetch("badge_type") }.sort
    assert_not_requested :any, /https?:/
  end

  test "the same snapshot seed and reference time reproduce the same plan without mutating catalog input" do
    before = @catalog.deep_dup
    first = build_baseline
    second = build_baseline

    assert_equal first, second
    assert_equal before, @catalog
    assert_equal 15, first.fetch("seed")
    assert_equal @as_of.iso8601(6), first.fetch("as_of")
    assert_equal @catalog.fetch("snapshot_id"), first.fetch("snapshot_id")
  end

  test "all 30 synthetic readers and the synthetic admin are active and use reserved email addresses" do
    users = build_baseline.fetch("users")

    assert_equal 30, users.count { |user| user.fetch("attributes").fetch("role") == "user" }
    assert_equal 1, users.count { |user| user.fetch("attributes").fetch("role") == "admin" }
    assert users.all? { |user| user.fetch("attributes").fetch("account_status") == "active" }
    assert users.all? { |user| user.fetch("attributes").fetch("email").end_with?("@example.test") }
    assert_equal 31, users.map { |user| user.fetch("attributes").fetch("email") }.uniq.length
    assert_equal 31, users.map { |user| user.fetch("attributes").fetch("nickname") }.uniq.length
    assert users.none? { |user| user.fetch("attributes").key?("password") || user.fetch("attributes").key?("encrypted_password") }
  end

  test "fictional display names are distinct while reader identities and login emails remain stable" do
    users = build_baseline.fetch("users")
    readers = users.select { |entry| entry.fetch("attributes").fetch("role") == "user" }

    assert_equal 31, users.map { |entry| entry.fetch("attributes").values_at("first_name", "last_name") }.uniq.length
    users.each do |entry|
      attributes = entry.fetch("attributes")
      assert_match(/\A[A-Z][a-z]+\z/, attributes.fetch("first_name"))
      assert_match(/\A[A-Z][a-z]+\z/, attributes.fetch("last_name"))
      assert_equal "#{attributes.fetch('first_name')}.#{attributes.fetch('last_name')}".downcase, attributes.fetch("nickname")
    end
    readers.each_with_index do |entry, index|
      identity = "reader#{format('%02d', index + 1)}"
      assert_equal identity, entry.fetch("identity")
      assert_equal "#{identity}@example.test", entry.fetch("attributes").fetch("email")
    end
    admin = users.find { |entry| entry.fetch("identity") == "admin" }
    assert_equal "reading_scenario_admin@example.test", admin.fetch("attributes").fetch("email")
  end

  test "default baseline dates stay reproducible across application time zones" do
    plans = [ "UTC", "America/Vancouver" ].map do |zone|
      Time.use_zone(zone) do
        Rails.stub(:env, "development".inquiry) do
          DevelopmentReadingScenarioPlan.new(catalog: @catalog).build_baseline
        end
      end
    end
    utc, pacific = plans

    assert_equal utc.fetch("reading_sessions"), pacific.fetch("reading_sessions")
    assert_equal utc.fetch("counts"), pacific.fetch("counts")
    assert_equal 0, Time.iso8601(utc.fetch("as_of")).utc_offset
    assert_not_equal 0, Time.iso8601(pacific.fetch("as_of")).utc_offset
    assert_equal Time.iso8601(utc.fetch("as_of")).to_date, Time.iso8601(pacific.fetch("as_of")).to_date
  end

  test "each reader has five distinct books and all three library states are represented" do
    library = build_baseline.fetch("user_books")

    assert_equal 150, library.map { |entry| [ entry.fetch("reader"), entry.fetch("work_key") ] }.uniq.length
    assert library.group_by { |entry| entry.fetch("reader") }.values.all? { |entries| entries.length == 5 }
    assert_equal UserBook::STATUSES.sort, library.map { |entry| entry.fetch("attributes").fetch("status") }.uniq.sort
    assert library.select { |entry| entry.fetch("attributes").fetch("status") == "finished" }.all? { |entry| entry.fetch("completion_note").include?("Synthetic manual completion") }
  end

  test "sessions reference a planned reading pair and never a want-to-read or manually finished pair" do
    plan = build_baseline
    library = plan.fetch("user_books").index_by { |entry| [ entry.fetch("reader"), entry.fetch("work_key") ] }

    assert plan.fetch("reading_sessions").all? { |session|
      entry = library.fetch([ session.fetch("reader"), session.fetch("work_key") ])
      entry.fetch("attributes").fetch("status") == "reading"
    }
    assert plan.fetch("reading_sessions").all? { |session| session.fetch("attributes").fetch("pages_read").positive? }
    assert_equal 300, plan.fetch("reading_sessions").map { |session| session.fetch("identity") }.uniq.length
  end

  test "all sessions fall inside the 28-day reference window and collectively cover all 28 dates" do
    sessions = build_baseline.fetch("reading_sessions")
    dates = sessions.map { |session| Date.iso8601(session.fetch("attributes").fetch("read_on")) }

    assert dates.all? { |date| (@as_of.to_date - 27..@as_of.to_date).cover?(date) }
    assert_equal 28, dates.uniq.length
    assert sessions.group_by { |session| [ session.fetch("reader"), session.fetch("attributes").fetch("read_on") ] }.values.any? { |entries| entries.length > 1 }
  end

  test "six readers per profile produce inactive steady lapsed recent and spiky activity" do
    plan = build_baseline
    readers = plan.fetch("users").select { |user| user.key?("profile") }
    profiles = readers.to_h { |reader| [ reader.fetch("identity"), reader.fetch("profile") ] }
    totals = plan.fetch("reading_sessions").group_by { |session| profiles.fetch(session.fetch("reader")) }.transform_values(&:length)

    assert_equal({ "inactive" => 6, "steady" => 6, "lapsed" => 6, "recent" => 6, "spiky" => 6 }, readers.group_by { |reader| reader.fetch("profile") }.transform_values(&:length))
    assert_equal({ "steady" => 144, "lapsed" => 48, "recent" => 48, "spiky" => 60 }, totals)
    plan.fetch("reading_sessions").group_by { |session| profiles.fetch(session.fetch("reader")) }.each do |profile, sessions|
      dates = sessions.map { |session| Date.iso8601(session.fetch("attributes").fetch("read_on")) }
      assert dates.all? { |date| date < @as_of.to_date - 7 } if profile == "lapsed"
      assert dates.all? { |date| date >= @as_of.to_date - 6 } if profile == "recent"
      assert_equal 48, dates.count { |date| date >= @as_of.to_date - 2 } if profile == "spiky"
    end
  end

  test "clubs have six members including one owner and the quiet club has no pick or messages" do
    plan = build_baseline
    memberships = plan.fetch("book_club_memberships")
    assert_equal 24, memberships.map { |entry| [ entry.fetch("club"), entry.fetch("reader") ] }.uniq.length

    plan.fetch("book_clubs").each do |club|
      members = memberships.select { |entry| entry.fetch("club") == club.fetch("identity") }
      assert_equal 6, members.length
      owners = members.select { |member| member.fetch("attributes").fetch("role") == "owner" }
      assert_equal [ club.fetch("owner") ], owners.map { |owner| owner.fetch("reader") }
    end
    quiet = plan.fetch("book_clubs").find { |club| club.fetch("identity") == "quiet" }
    assert_nil quiet.fetch("current_work_key")
    assert plan.fetch("club_messages").none? { |message| message.fetch("club") == "quiet" }
    assert_equal({ "steady" => 27, "lapsed" => 27, "recent" => 26 }, plan.fetch("club_messages").group_by { |message| message.fetch("club") }.transform_values(&:length))
    assert_equal 6, plan.fetch("users").count { |user| user.key?("profile") && memberships.none? { |entry| entry.fetch("reader") == user.fetch("identity") } }
  end

  test "at least ten selected Works have no planned library session review or club-pick activity" do
    plan = build_baseline
    active_keys = [ "user_books", "reading_sessions", "reviews" ].flat_map { |name| plan.fetch(name).map { |entry| entry.fetch("work_key") } }
    active_keys.concat(plan.fetch("book_clubs").filter_map { |club| club.fetch("current_work_key") })
    reserved = plan.fetch("zero_activity_work_keys")

    assert_equal 10, reserved.length
    assert_empty reserved & active_keys
    assert_empty active_keys.uniq - @catalog.fetch("books").map { |entry| entry.fetch("book_attributes").fetch("ol_work_key") }
  end

  test "the reserved reader and club-pick pair has exactly two sessions totaling 25 with maximum 15" do
    plan = build_baseline
    example = plan.fetch("page_semantics_example")
    pages = plan.fetch("reading_sessions").select { |session|
      session.fetch("reader") == example.fetch("reader") && session.fetch("work_key") == example.fetch("work_key")
    }.map { |session| session.fetch("attributes").fetch("pages_read") }

    assert_equal [ 10, 15 ], pages
    assert_equal 25, pages.sum
    assert_equal 15, pages.max
    assert_equal example.fetch("work_key"), plan.fetch("book_clubs").first.fetch("current_work_key")
  end

  test "discussion authors are club members and visible text contains no technical identities or private notes" do
    plan = build_baseline
    member_pairs = plan.fetch("book_club_memberships").map { |entry| [ entry.fetch("club"), entry.fetch("reader") ] }
    messages = plan.fetch("club_messages")

    assert messages.all? { |message| member_pairs.include?([ message.fetch("club"), message.fetch("reader") ]) }
    assert messages.all? { |message| message.fetch("attributes").fetch("parent_id").nil? }
    assert messages.all? { |message| message.fetch("attributes").fetch("body").length <= 1_000 }
    assert messages.any? { |message| message.fetch("attributes").fetch("body").length > 500 }
    assert messages.all? { |message|
      body = message.fetch("attributes").fetch("body")
      body.include?("café") && !body.include?(message.fetch("identity")) && !body.include?("@example.test") && !body.include?("Synthetic journal")
    }
  end

  test "reviews have valid ratings and unique reader-book pairs already marked as manually finished" do
    plan = build_baseline
    reviews = plan.fetch("reviews")
    finished = plan.fetch("user_books").select { |entry| entry.fetch("attributes").fetch("status") == "finished" }
      .map { |entry| [ entry.fetch("reader"), entry.fetch("work_key") ] }

    assert_equal 20, reviews.map { |review| [ review.fetch("reader"), review.fetch("work_key") ] }.uniq.length
    assert reviews.all? { |review| (0..5).cover?(review.fetch("attributes").fetch("rating")) }
    assert reviews.all? { |review| finished.include?([ review.fetch("reader"), review.fetch("work_key") ]) }
    assert reviews.all? { |review| review.fetch("attributes").fetch("body").start_with?("Synthetic review:") }
  end

  test "non-development planning refuses without making HTTP requests" do
    [ "test", "production" ].each do |environment|
      Rails.stub(:env, environment.inquiry) do
        assert_raises(RuntimeError) { @builder.build_baseline }
      end
    end

    assert_not_requested :any, /https?:/
  end

  private

  def build_baseline
    Rails.stub(:env, "development".inquiry) { @builder.build_baseline }
  end
end
