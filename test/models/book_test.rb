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
end
