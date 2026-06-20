require "test_helper"

class BookTest < ActiveSupport::TestCase
  def setup
    @book = Book.new(title: "Clean Code", author: "Robert Martin", total_pages: 431)
  end

  test "valid book is valid" do
    assert @book.valid?
  end

  test "title is required" do
    @book.title = ""
    assert_not @book.valid?
  end

  test "author is required" do
    @book.author = ""
    assert_not @book.valid?
  end

  test "total_pages is optional" do
    @book.total_pages = nil
    assert @book.valid?
  end

  test "title and author are titleized before save" do
    book = Book.create!(title: "the great gatsby", author: "f. scott fitzgerald", total_pages: 180)
    assert_equal "The Great Gatsby", book.title
    assert_equal "F. Scott Fitzgerald", book.author
  end
end
