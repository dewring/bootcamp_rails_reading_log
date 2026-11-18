class DevelopmentReadingScenarioActivity::References
  attr_reader :users, :books, :edition_ids

  def initialize(manifest:)
    @manifest = manifest
  end

  def load_references
    user_records = @manifest.fetch("bootstrap").fetch("records").fetch("users")
    book_records = @manifest.fetch("catalog").fetch("records")
    users = User.where(id: user_records.values.map { |record| record.fetch("id") }).index_by(&:id)
    books = Book.where(id: book_records.values.map { |pair| pair.fetch("book").fetch("id") }).index_by(&:id)
    @users = user_records.transform_values do |record|
      users.fetch(record.fetch("id"))
    end
    @books = book_records.to_h do |work_key, pair|
      record = pair.fetch("book")
      book = books[record["id"]]
      book = nil if record["result"] == "skipped" || book&.ol_work_key != work_key
      [ work_key, book ]
    end
    recorded_edition_ids = book_records.values.filter_map { |pair| pair.fetch("edition")["id"] }
    editions = BookEdition.where(id: recorded_edition_ids).index_by(&:id)
    @edition_ids = book_records.transform_values do |pair|
      edition_record = pair.fetch("edition")
      edition = editions[edition_record["id"]]
      expected_key = edition_record.dig("expected_attributes", "ol_edition_key")
      if edition && edition.book_id == pair.fetch("book").fetch("id") && edition.ol_edition_key == expected_key
        edition.id
      end
    end
    self
  end

  def update_pending_session_edition(record, work_key:)
    expected = record.fetch("expected_attributes")
    edition_id = @edition_ids.fetch(work_key)
    return false if expected["book_edition_id"] == edition_id

    expected["book_edition_id"] = edition_id
    true
  end
end
