require "test_helper"

class BookEditionTest < ActiveSupport::TestCase
  def setup
    @book = Book.create!(title: "Harry Potter", author: "J. K. Rowling", ol_work_key: "/works/OL45804W")
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
end
