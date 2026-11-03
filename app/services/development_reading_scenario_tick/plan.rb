class DevelopmentReadingScenarioTick::Plan
  NAME = "tick1".freeze

  def initialize(baseline:, manifest:, as_of:)
    @baseline = baseline
    @manifest = manifest
    @as_of = as_of.in_time_zone
  end

  def build_tick
    targets = [ [ "steady", "reader08" ], [ "lapsed", "reader14" ], [ "recent", "reader20" ] ]
    sessions = targets.each_with_index.to_h do |(club, reader), index|
      work = @baseline.fetch("book_clubs").find { |entry| entry.fetch("identity") == club }.fetch("current_work_key")
      book = @manifest.fetch("catalog").fetch("records").fetch(work)
      [ "reading#{index + 1}", {
        "id" => nil, "result" => nil, "library_identity" => "#{reader}/#{work}",
        "expected_attributes" => {
          "user_id" => reader_id(reader), "book_id" => book.fetch("book").fetch("id"),
          "book_edition_id" => book.fetch("edition")["id"], "read_on" => @as_of.to_date.iso8601,
          "pages_read" => 16 + index,
          "notes" => "Synthetic journal. Follow-up reading: I revisited a passage and compared it with my earlier notes."
        }
      } ]
    end
    posts = targets.first(2).each_with_index.to_h do |(club, reader), index|
      [ "discussion#{index + 1}", {
        "id" => nil, "result" => nil,
        "expected_attributes" => {
          "user_id" => reader_id(reader),
          "book_club_id" => @manifest.fetch("community").fetch("records").fetch("book_clubs").fetch(club).fetch("id"),
          "parent_id" => nil,
          "body" => "Synthetic discussion. After another reading break, I noticed how the opening passage changes my interpretation of the chapter."
        }
      } ]
    end
    { "name" => NAME, "status" => "pending", "expected_counts" => { "reading_sessions" => 3, "club_messages" => 2 },
      "reading_sessions" => sessions, "club_messages" => posts }
  end

  private

  def reader_id(identity)
    @manifest.fetch("bootstrap").fetch("records").fetch("users").fetch(identity).fetch("id")
  end
end
