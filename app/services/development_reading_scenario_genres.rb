class DevelopmentReadingScenarioGenres
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
    book_ids = @manifest.fetch("catalog").fetch("records").values.filter_map do |pair|
      book = pair.fetch("book")
      book["id"] unless [ "skipped", "failed" ].include?(book["result"])
    end
    @books = Book.where(id: book_ids).order(:id).to_a
    @available_book_ids = @books.map(&:id).to_set
    @available_genre_ids = @manifest.fetch("bootstrap").fetch("records").fetch("genres").transform_values do |record|
      record["id"] unless [ "skipped", "failed" ].include?(record["result"])
    end
    @rows = BookGenre.where(book_id: book_ids).index_by { |row| [ row.book_id, row.genre_id ] }
    @manifest["book_genres"] ||= { "status" => "pending", "records" => {} }
    records = @manifest.fetch("book_genres").fetch("records")
    records.reverse_merge!(planned_links)
    reconcile_recorded_links(records)
    @scenario_manifest.save_scenario

    active_records = records.values.reject { |record| record["result"] == "skipped" }
    missing = active_records.reject { |record| @rows.key?(link_pair(record)) }
    # This model has no callbacks; the composite unique index makes concurrent insertion safe without overwriting links.
    if missing.any?
      BookGenre.insert_all(missing.map { |record| record.slice("book_id", "genre_id") }, unique_by: [ :book_id, :genre_id ])
    end
    saved = BookGenre.where(book_id: book_ids).index_by { |row| [ row.book_id, row.genre_id ] }
    active_records.each { |record| record["id"] = saved.fetch(link_pair(record)).id }
    @manifest.fetch("book_genres").merge!("status" => "complete", "actual_count" => active_records.length)
    @scenario_manifest.save_scenario
    @manifest.deep_dup
  end

  private

  def planned_links
    @books.flat_map do |book|
      genre_names(book.subjects).map do |name|
        genre_id = @available_genre_ids.fetch(name)
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

  def reconcile_recorded_links(records)
    records.each do |identity, record|
      unless @available_book_ids.include?(record.fetch("book_id"))
        record.merge!("result" => "skipped", "reason" => "book_unavailable")
        next
      end
      genre_id = @available_genre_ids.fetch(identity.split("/").last)
      unless genre_id && (record["genre_id"].nil? || record["genre_id"] == genre_id)
        record.merge!("result" => "skipped", "reason" => "genre_unavailable")
        next
      end
      if record["genre_id"].nil?
        record["genre_id"] = genre_id
        record.except!("result", "reason")
      end
      next unless record["id"]

      row = @rows[link_pair(record)]
      unless row
        record.merge!("result" => "skipped", "reason" => "recorded_genre_link_missing")
        next
      end
      record["origin"] = "reused" if row.id != record.fetch("id")
      record.except!("result", "reason")
    end
  end

  def link_pair(record)
    record.values_at("book_id", "genre_id")
  end
end
