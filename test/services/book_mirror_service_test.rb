require "test_helper"

class BookMirrorServiceTest < ActiveSupport::TestCase
  def setup
    Rails.cache.clear
    @book = Book.create!(
      title: "Harry Potter",
      author: "J. K. Rowling",
      ol_work_key: "/works/OL45804W"
    )
  end

  test "returns nil when fetch_work returns nil" do
    stub_request(:get, "https://openlibrary.org/works/OL45804W.json")
      .to_raise(Faraday::TimeoutError)

    result = BookMirrorService.new("OL45804W").call
    assert_nil result
  end

  test "enriches book with description and subjects" do
    stub_request(:get, "https://openlibrary.org/works/OL45804W.json")
      .to_return(
        status: 200,
        body: {
          title: "Harry Potter",
          description: "A story about a wizard",
          subjects: [ "Magic", "Wizards", "Fantasy" ]
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    stub_request(:get, "https://openlibrary.org/works/OL45804W/editions.json")
      .to_return(
        status: 200,
        body: '{"entries": []}',
        headers: { "Content-Type" => "application/json" }
      )

    result = BookMirrorService.new("OL45804W").call
    assert_equal "A story about a wizard", result.description
    assert_includes result.subjects, "Magic"
  end

  test "mirror_editions is idempotent" do
    stub_request(:get, "https://openlibrary.org/works/OL45804W.json")
      .to_return(
        status: 200,
        body: { title: "Harry Potter", description: "A wizard", subjects: [] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    stub_request(:get, "https://openlibrary.org/works/OL45804W/editions.json")
      .to_return(
        status: 200,
        body: {
          entries: [ { key: "/books/OL123M", publishers: [ "Scholastic" ] } ]
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    BookMirrorService.new("OL45804W").call
    assert_no_difference "BookEdition.count" do
      BookMirrorService.new("OL45804W").call
    end
  end
  test "mirror_editions saves title from Open Library" do
    stub_request(:get, "https://openlibrary.org/works/OL45804W.json")
      .to_return(
        status: 200,
        body: { title: "Harry Potter", description: "A wizard", subjects: [] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    stub_request(:get, "https://openlibrary.org/works/OL45804W/editions.json")
      .to_return(
        status: 200,
        body: {
          entries: [ { key: "/books/OL999M", title: "Harry Potter" } ]
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    BookMirrorService.new("OL45804W").call

    edition = BookEdition.find_by(ol_edition_key: "/books/OL999M")
    assert_equal "Harry Potter", edition.title
  end

  test "mirror_editions updates title on existing edition" do
    BookEdition.create!(ol_edition_key: "/books/OL999M", book: @book, title: nil)

    stub_request(:get, "https://openlibrary.org/works/OL45804W.json")
      .to_return(
        status: 200,
        body: { "description" => "A great book", "subjects" => [], "covers" => [] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    stub_request(:get, "https://openlibrary.org/works/OL45804W/editions.json")
      .to_return(
        status: 200,
        body: { entries: [ { key: "/books/OL999M", title: "Harry Potter" } ] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    BookMirrorService.new("OL45804W").call

    edition = BookEdition.find_by(ol_edition_key: "/books/OL999M")
    assert_equal "Harry Potter", edition.title
  end
end
