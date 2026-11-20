class DevelopmentReadingScenarioPlan
  class ReferenceTimeError < ArgumentError; end

  READER_NAMES = [
    "Maya Chen", "Liam Patel", "Sofia Rivera", "Noah Brooks", "Amelia Kim", "Ethan Wilson",
    "Olivia Bennett", "Lucas Nguyen", "Isabella Ortiz", "Mason Clarke", "Charlotte Evans", "James Park",
    "Harper Lewis", "Benjamin Shah", "Evelyn Reed", "Elijah Santos", "Abigail Turner", "Henry Zhao",
    "Ella Mitchell", "Alexander Costa", "Grace Martin", "Daniel Ahmed", "Chloe Wright", "Samuel Ito",
    "Nora Campbell", "David Okafor", "Lily Thompson", "Joseph Silva", "Zoe Anderson", "Gabriel Rossi"
  ].freeze
  BADGES = [
    { "badge_type" => "first_session", "name" => "First Session", "description" => "Logged your first reading session." },
    { "badge_type" => "week_streak", "name" => "Week Streak", "description" => "Read for 7 or more days in a row." },
    { "badge_type" => "bookworm", "name" => "Bookworm", "description" => "Finished 5 or more books." },
    { "badge_type" => "challenge_complete", "name" => "Challenge Complete", "description" => "Completed a reading challenge." },
    { "badge_type" => "page_turner", "name" => "Page Turner", "description" => "Logged 500 or more total pages read." }
  ].freeze

  def self.configured_reference_time
    configured_time = ENV["READING_SCENARIO_AS_OF"]
    return if configured_time.nil?

    unless configured_time.match?(/(?:Z|[+-]\d{2}:\d{2})\z/)
      raise ReferenceTimeError, "READING_SCENARIO_AS_OF must be an ISO 8601 timestamp with Z or an explicit UTC offset"
    end

    Time.iso8601(configured_time).in_time_zone
  rescue ArgumentError
    raise ReferenceTimeError, "READING_SCENARIO_AS_OF must be a valid ISO 8601 timestamp with Z or an explicit UTC offset"
  end

  def initialize(as_of: DevelopmentReadingScenarioPlan.configured_reference_time)
    @as_of = (as_of || Time.current).in_time_zone
  end

  def static_records
    @readers = readers
    challenges = challenge_entries
    {
      "as_of" => @as_of.iso8601(6),
      "genres" => Genre::GENRES.map { |name| { "name" => name } }, "badges" => BADGES,
      "users" => @readers + [ administrator ], "challenges" => challenges,
      "user_challenges" => challenge_enrollments(challenges)
    }
  end

  private

  def challenge_entries
    goals = [
      [ "daily10", "Daily Ten Pages", "pages_per_day", 10 ],
      [ "daily25", "Daily Twenty-Five Pages", "pages_per_day", 25 ],
      [ "books2", "Finish Two Books", "books_total", 2 ],
      [ "books5", "Finish Five Books", "books_total", 5 ],
      [ "streak7", "Seven-Day Reading Streak", "streak_days", 7 ],
      [ "streak14", "Fourteen-Day Reading Streak", "streak_days", 14 ]
    ]
    goals.map do |identity, title, goal_type, goal_value|
      {
        "identity" => identity,
        "attributes" => {
          "title" => "Demo: #{title}", "goal_type" => goal_type, "goal_value" => goal_value,
          "starts_at" => (@as_of - 27.days).iso8601(6), "ends_at" => (@as_of + 60.days).iso8601(6), "active" => true
        }
      }
    end
  end

  def challenge_enrollments(challenges)
    # Leave the last ten readers unenrolled to demonstrate the empty state.
    @readers.first(20).each_with_index.flat_map do |reader, index|
      number_of_challenges = index < 10 ? 3 : 1
      Array.new(number_of_challenges) do |offset|
        challenge = challenges.fetch((index + offset) % challenges.length).fetch("identity")
        {
          "identity" => "#{reader.fetch('identity')}/#{challenge}",
          "reader" => reader.fetch("identity"), "challenge" => challenge
        }
      end
    end
  end

  def readers
    READER_NAMES.each_with_index.map do |name, index|
      number = format("%02d", index + 1)
      first_name, last_name = name.split(" ", 2)
      {
        "identity" => "reader#{number}",
        "attributes" => {
          "first_name" => first_name, "last_name" => last_name,
          "nickname" => name.downcase.tr(" ", "."), "email" => "reader#{number}@example.test",
          "role" => "user", "account_status" => "active"
        }
      }
    end
  end

  def administrator
    {
      "identity" => "admin",
      "attributes" => {
        "first_name" => "Avery", "last_name" => "Morgan",
        "nickname" => "avery.morgan", "email" => "reading_scenario_admin@example.test",
        "role" => "admin", "account_status" => "active"
      }
    }
  end
end
