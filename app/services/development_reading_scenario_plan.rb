class DevelopmentReadingScenarioPlan
  SEED = 15
  PROFILES = [ "inactive", "steady", "lapsed", "recent", "spiky" ].freeze
  SESSIONS_PER_READER = { "inactive" => 0, "steady" => 24, "lapsed" => 8, "recent" => 8, "spiky" => 10 }.freeze
  BADGES = [
    { "badge_type" => "first_session", "name" => "First Session", "description" => "Logged your first reading session." },
    { "badge_type" => "week_streak", "name" => "Week Streak", "description" => "Read for 7 or more days in a row." },
    { "badge_type" => "bookworm", "name" => "Bookworm", "description" => "Finished 5 or more books." },
    { "badge_type" => "challenge_complete", "name" => "Challenge Complete", "description" => "Completed a reading challenge." },
    { "badge_type" => "page_turner", "name" => "Page Turner", "description" => "Logged 500 or more total pages read." }
  ].freeze

  def self.default_reference_time
    Time.zone.local(2026, 10, 30, 12)
  end

  def initialize(catalog:, as_of: DevelopmentReadingScenarioPlan.default_reference_time)
    @catalog = catalog
    @as_of = as_of.in_time_zone
  end

  def build_baseline
    raise "Scenario planning is only available in development" unless Rails.env.development?

    @work_keys = @catalog.fetch("books").map { |entry| entry.fetch("book_attributes").fetch("ol_work_key") }
    unless @work_keys.length == 100 && @work_keys.uniq.length == 100
      raise ArgumentError, "The baseline requires exactly 100 distinct captured Works"
    end
    @random = Random.new(SEED)
    @activity_keys = @work_keys.first(90).shuffle(random: @random)
    @readers = readers
    @library = library_entries
    clubs = book_clubs
    sessions = reading_sessions
    memberships = club_memberships(clubs)
    messages = club_messages(clubs)
    review_entries = reviews
    {
      "snapshot_id" => @catalog.fetch("snapshot_id"), "seed" => SEED, "as_of" => @as_of.iso8601(6),
      "genres" => Genre::GENRES.map { |name| { "name" => name } },
      "badges" => BADGES.deep_dup,
      "users" => @readers + [ administrator ], "user_books" => @library,
      "reading_sessions" => sessions, "book_clubs" => clubs,
      "book_club_memberships" => memberships, "club_messages" => messages, "reviews" => review_entries,
      "zero_activity_work_keys" => @work_keys.last(10),
      "page_semantics_example" => { "reader" => "reader07", "work_key" => @activity_keys.first },
      "counts" => {
        "books" => 100, "book_editions" => @catalog.fetch("books").count { |entry| entry["edition_attributes"] },
        "users" => @readers.length + 1, "user_books" => @library.length,
        "reading_sessions" => sessions.length, "book_clubs" => clubs.length,
        "book_club_memberships" => memberships.length, "club_messages" => messages.length, "reviews" => review_entries.length
      }
    }
  end

  private

  def readers
    Array.new(30) do |index|
      number = format("%02d", index + 1)
      {
        "identity" => "reader#{number}", "profile" => PROFILES.fetch(index / 6),
        "attributes" => {
          "first_name" => "Synthetic", "last_name" => "Reader #{number}",
          "nickname" => "reading_scenario_reader#{number}", "email" => "reader#{number}@example.test",
          "role" => "user", "account_status" => "active"
        }
      }
    end
  end

  def administrator
    {
      "identity" => "admin",
      "attributes" => {
        "first_name" => "Synthetic", "last_name" => "Administrator",
        "nickname" => "reading_scenario_admin", "email" => "reading_scenario_admin@example.test",
        "role" => "admin", "account_status" => "active"
      }
    }
  end

  def library_entries
    @readers.each_with_index.flat_map do |reader, index|
      Array.new(5) do |slot|
        key = library_work_key(index, slot)
        status = library_status(reader, slot)
        {
          "identity" => "#{reader.fetch('identity')}/#{key}", "reader" => reader.fetch("identity"), "work_key" => key,
          "attributes" => { "status" => status },
          "completion_note" => status == "finished" ? "Synthetic manual completion: finished before session tracking began." : nil
        }
      end
    end
  end

  def library_work_key(reader_index, slot)
    return @activity_keys.fetch(30 + reader_index * 5 + slot) if reader_index < 6
    return @activity_keys.fetch(reader_index < 24 ? (reader_index - 6) / 6 : 3 + reader_index - 24) if slot.zero?

    @activity_keys.fetch(9 + ((reader_index - 6) * 4 + slot - 1) % 81)
  end

  def library_status(reader, slot)
    return "want_to_read" if reader.fetch("profile") == "inactive" || slot == 4
    return "finished" if slot == 3

    "reading"
  end

  def reading_sessions
    @readers.each_with_index.flat_map do |reader, reader_index|
      count = SESSIONS_PER_READER.fetch(reader.fetch("profile"))
      Array.new(count) do |index|
        example = reader.fetch("identity") == "reader07"
        slot = session_library_slot(reader, index)
        pages = example && index < 2 ? [ 10, 15 ].fetch(index) : @random.rand(1..15)
        {
          "identity" => "#{reader.fetch('identity')}/reading#{format('%02d', index + 1)}",
          "reader" => reader.fetch("identity"), "work_key" => library_work_key(reader_index, slot),
          "attributes" => {
            "read_on" => (@as_of.to_date - 27 + session_day_offset(reader.fetch("profile"), reader_index % 6, index)).iso8601,
            "pages_read" => pages,
            "notes" => "Synthetic journal. Reading #{index + 1}: I compared this passage with my earlier notes over a café break."
          }
        }
      end
    end
  end

  def session_library_slot(reader, index)
    return index % 3 unless reader.fetch("identity") == "reader07"
    return 0 if index < 2

    1 + index % 2
  end

  def session_day_offset(profile, reader_offset, index)
    case profile
    when "steady"
      (index + reader_offset * 4) % 28
    when "lapsed"
      index + reader_offset % 4
    when "recent"
      21 + (index + reader_offset) % 7
    when "spiky"
      index < 2 ? (reader_offset + index * 7) % 21 : 25 + index % 3
    end
  end

  def book_clubs
    [ "steady", "lapsed", "recent", "quiet" ].each_with_index.map do |name, index|
      {
        "identity" => name, "owner" => @readers.fetch(6 + index * 6).fetch("identity"),
        "current_work_key" => index < 3 ? @activity_keys.fetch(index) : nil,
        "attributes" => {
          "name" => "Reading Scenario #{name.capitalize} Readers",
          "description" => "Synthetic development club for #{name} reading activity.",
          "reading_deadline" => index < 3 ? (@as_of.to_date + 14).iso8601 : nil
        }
      }
    end
  end

  def club_memberships(clubs)
    clubs.each_with_index.flat_map do |club, index|
      @readers.slice(6 + index * 6, 6).map do |reader|
        {
          "identity" => "#{club.fetch('identity')}/#{reader.fetch('identity')}",
          "club" => club.fetch("identity"), "reader" => reader.fetch("identity"),
          "attributes" => { "role" => reader.fetch("identity") == club.fetch("owner") ? "owner" : "member" }
        }
      end
    end
  end

  def club_messages(clubs)
    clubs.first(3).each_with_index.flat_map do |club, club_index|
      Array.new([ 27, 27, 26 ].fetch(club_index)) do |index|
        body = "Synthetic discussion. Reflection #{index + 1}: I compared today's reading with my earlier notes over a café break."
        if club_index.zero? && index.zero?
          body = body.concat(" I am taking time to revisit passages, compare interpretations, and explain which details changed my first impression." * 5)
        end
        {
          "identity" => "#{club.fetch('identity')}/reflection#{format('%02d', index + 1)}",
          "club" => club.fetch("identity"), "reader" => @readers.fetch(6 + club_index * 6 + index % 6).fetch("identity"),
          "attributes" => { "body" => body, "parent_id" => nil }
        }
      end
    end
  end

  def reviews
    @readers.drop(6).first(20).map do |reader|
      book = @library.find { |entry| entry.fetch("reader") == reader.fetch("identity") && entry.fetch("attributes").fetch("status") == "finished" }
      {
        "identity" => "#{reader.fetch('identity')}/review", "reader" => reader.fetch("identity"), "work_key" => book.fetch("work_key"),
        "attributes" => { "rating" => @random.rand(1..5), "body" => "Synthetic review: I finished this before tracking sessions and enjoyed comparing my notes during a café discussion." }
      }
    end
  end
end
