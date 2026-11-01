class DevelopmentReadingScenarioActivity::References
  attr_reader :users, :books, :edition_ids

  def initialize(plan:, manifest:)
    @plan = plan
    @manifest = manifest
  end

  def load_references
    unless @manifest.dig("bootstrap", "status") == "complete" && @manifest.dig("catalog", "status") == "complete"
      raise DevelopmentReadingScenarioActivity::ActivityError, "Complete bootstrap and catalog replay before importing reading activity."
    end
    user_records = @manifest.fetch("bootstrap").fetch("records").fetch("users")
    book_records = @manifest.fetch("catalog").fetch("records")
    users = User.where(id: user_records.values.map { |record| record.fetch("id") }).index_by(&:id)
    books = Book.where(id: book_records.values.map { |pair| pair.fetch("book").fetch("id") }).index_by(&:id)
    @users = @plan.fetch("users").to_h do |entry|
      identity = entry.fetch("identity")
      record = user_records.fetch(identity)
      row = users[record.fetch("id")]
      verify_reference(record, row, "user #{identity}")
      unless row.attributes.slice(*entry.fetch("attributes").keys) == entry.fetch("attributes")
        raise DevelopmentReadingScenarioActivity::ActivityError, "User #{identity} (ID #{row.id}) differs from the synthetic account plan."
      end
      [ identity, row ]
    end
    @books = book_records.to_h do |key, pair|
      row = books[pair.fetch("book").fetch("id")]
      verify_reference(pair.fetch("book"), row, key)
      raise DevelopmentReadingScenarioActivity::ActivityError, "Book #{key} changed its external identity." unless row.ol_work_key == key

      [ key, row ]
    end
    edition_records = book_records.values.filter_map { |pair| pair.fetch("edition") if pair.fetch("edition")["id"] }
    editions = BookEdition.where(id: edition_records.map { |record| record.fetch("id") }).index_by(&:id)
    edition_records.each { |record| verify_reference(record, editions[record.fetch("id")], "Edition #{record.fetch('id')}") }
    @edition_ids = book_records.transform_values { |pair| pair.fetch("edition")["id"] }
    self
  end

  private

  def verify_reference(record, row, label)
    raise DevelopmentReadingScenarioActivity::ActivityError, "Recorded #{label} (ID #{record['id']}) is missing." unless row

    expected = record.fetch("expected_attributes")
    unless recorded_attributes(row).slice(*expected.keys) == expected
      raise DevelopmentReadingScenarioActivity::ActivityError, "Recorded #{label} (ID #{row.id}) changed; no reading data was imported."
    end
  end

  def recorded_attributes(row)
    JSON.parse(row.attributes.except("id", "updated_at", "remember_created_at", "reset_password_token", "reset_password_sent_at").to_json)
  end
end
