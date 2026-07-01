require "test_helper"

class BookEditionTest < ActiveSupport::TestCase
  def setup
    @book = Book.create!(title: "Harry Potter", author: "J. K. Rowling")
    @edition = BookEdition.new(book: @book, ol_edition_key: "/books/OL123M")
  end

  test "valid edition is valid" do
    assert @edition.valid?
  end

  test "ol_edition_key is required" do
    @edition.ol_edition_key = nil
    assert_not @edition.valid?
  end

  test "belongs to a book" do
    assert_equal @book, @edition.book
  end

  test "creating a BookEdition clears the editions cache" do
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    book = Book.create!(
      title: "Harry Potter",
      author: "J. K. Rowling"
    )
    Rails.cache.write("book:#{book.id}:editions:list", [ "fake" ])

    BookEdition.create!(ol_edition_key: "/books/OL001M", book: book)

    assert_nil Rails.cache.read("book:#{book.id}:editions:list")
  end

  test "destroying a BookEdition clears the editions cache" do
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    book = Book.create!(
      title: "Harry Potter",
      author: "J. K. Rowling"
    )
    edition = BookEdition.create!(ol_edition_key: "/books/OL001M", book: book)
    Rails.cache.write("book:#{book.id}:editions:list", [ "fake" ])

    edition.destroy!

    assert_nil Rails.cache.read("book:#{book.id}:editions:list")
  end
end
