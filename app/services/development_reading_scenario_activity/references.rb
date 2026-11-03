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
    @books = book_records.transform_values do |pair|
      books.fetch(pair.fetch("book").fetch("id"))
    end
    @edition_ids = book_records.transform_values { |pair| pair.fetch("edition")["id"] }
    self
  end
end
