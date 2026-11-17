class DevelopmentReadingScenarioGenres
  class GenreError < StandardError; end

  SUBJECT_PATTERNS = {
    "Fiction" => /\bfiction\b/i,
    "Non-Fiction" => /\bnon[ -]?fiction\b/i,
    "Mystery" => /\bmyster(?:y|ies)\b/i,
    "Thriller" => /\bthrillers?\b/i,
    "Romance" => /\bromance\b/i,
    "Fantasy" => /\bfantas(?:y|ies)\b/i,
    "Science-Fiction" => /\bscience[ -]fiction\b/i,
    "Biography" => /\b(?:biograph(?:y|ies)|autobiograph(?:y|ies))\b/i,
    "History" => /\bhistory\b/i,
    "Self-Help" => /\bself[ -]help\b/i,
    "Horror" => /\bhorror\b/i,
    "Poetry" => /\b(?:poetry|poems?)\b/i
  }.freeze

  def initialize(manifest:, scenario_manifest:)
    @manifest = manifest
    @scenario_manifest = scenario_manifest
  end

  def seed_genres
    book_ids = @manifest.fetch("catalog").fetch("records").values.map { |pair| pair.fetch("book").fetch("id") }
    @books = Book.where(id: book_ids).order(:id).to_a
    @rows = BookGenre.where(book_id: book_ids).index_by { |row| [ row.book_id, row.genre_id ] }
    @manifest["book_genres"] ||= { "status" => "pending", "records" => planned_links }
    records = @manifest.fetch("book_genres").fetch("records")
    verify_recorded_links(records)
    @scenario_manifest.save_scenario

    missing = records.values.reject { |record| @rows.key?([ record.fetch("book_id"), record.fetch("genre_id") ]) }
    # This model has no callbacks; the composite unique index makes concurrent insertion safe without overwriting links.
    if missing.any?
      BookGenre.insert_all(missing.map { |record| record.slice("book_id", "genre_id") }, unique_by: [ :book_id, :genre_id ])
    end
    saved = BookGenre.where(book_id: book_ids).index_by { |row| [ row.book_id, row.genre_id ] }
    records.each_value { |record| record["id"] = saved.fetch([ record.fetch("book_id"), record.fetch("genre_id") ]).id }
    @manifest.fetch("book_genres").merge!("status" => "complete", "actual_count" => records.length)
    @scenario_manifest.save_scenario
    @manifest.deep_dup
  end

  private

  def planned_links
    genres = @manifest.fetch("bootstrap").fetch("records").fetch("genres")
    @books.flat_map do |book|
      genre_names(book.subjects).map do |name|
        genre_id = genres.fetch(name).fetch("id")
        existing = @rows[[ book.id, genre_id ]]
        [ "#{book.ol_work_key}/#{name}", {
          "id" => existing&.id, "book_id" => book.id, "genre_id" => genre_id,
          "origin" => existing ? "reused" : "imported"
        } ]
      end
    end.to_h
  end

  def genre_names(subjects)
    SUBJECT_PATTERNS.filter_map do |name, pattern|
      matched = Array(subjects).any? do |subject|
        next false if name == "Fiction" && subject.match?(SUBJECT_PATTERNS.fetch("Non-Fiction"))

        subject.match?(pattern)
      end
      name if matched
    end
  end

  def verify_recorded_links(records)
    records.each do |identity, record|
      next unless record["id"]

      row = @rows[[ record.fetch("book_id"), record.fetch("genre_id") ]]
      unless row && row.id == record.fetch("id")
        raise GenreError, "Recorded genre link #{identity} (ID #{record.fetch('id')}) is missing or changed; no automatic recreation is allowed."
      end
    end
  end
end
