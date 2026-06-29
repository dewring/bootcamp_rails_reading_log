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

  test "find_or_create_from_search_result creates a book from a search doc" do
    doc = {
      "key"         => "/works/OL82563W",
      "title"       => "Harry Potter",
      "author_name" => [ "J. K. Rowling" ]
    }

    book = Book.find_or_create_from_search_result(doc)

    assert_equal "/works/OL82563W", book.ol_work_key
    assert_equal "Harry Potter", book.title
    assert_equal "J. K. Rowling", book.author
  end

  test "does not create duplicate books" do
    doc = {
      "key"         => "/works/OL82563W",
      "title"       => "Harry Potter",
      "author_name" => [ "J. K. Rowling" ]
    }

    Book.find_or_create_from_search_result(doc)
    assert_no_difference "Book.count" do
      Book.find_or_create_from_search_result(doc)
    end
  end
  test "returns nil when doc key is blank" do
    doc = { "key" => nil, "title" => "Harry Potter", "author_name" => [ "J. K. Rowling" ] }

    result = Book.find_or_create_from_search_result(doc)

    assert_nil result
  end
end
