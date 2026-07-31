require "test_helper"

class OpenLibraryClientTest < ActiveSupport::TestCase
  test "search returns docs array" do
    stub_request(:get, "https://openlibrary.org/search.json")
      .with(query: { q: "Harry Potter", page: 1, limit: 10 })
      .to_return(
        status: 200,
        body: '{"docs": [{"key": "/works/OL82563W", "title": "Harry Potter"}], "numFound": 1000}',
        headers: { "Content-Type" => "application/json" }
      )

    result = OpenLibraryClient.new.search("Harry Potter")
    assert_not_empty result[:docs]
    assert result[:docs].first.key?("key")
    assert_equal 1000, result[:total]
  end

  test "search returns empty array on Faraday error" do
    stub_request(:get, "https://openlibrary.org/search.json")
      .with(query: { q: "anything", page: 1, limit: 10 })
      .to_raise(Faraday::TimeoutError)

    result = OpenLibraryClient.new.search("anything")
    assert_equal({ docs: [], total: 0 }, result)
  end

  test "search returns empty docs when OpenLibrary rejects the query" do
    stub_request(:get, "https://openlibrary.org/search.json")
      .with(query: { q: "a", page: 1, limit: 10 })
      .to_return(
        status: 422,
        body: '{"detail": [{"type": "value_error", "msg": "Query too short"}]}',
        headers: { "Content-Type" => "application/json" }
      )

    result = OpenLibraryClient.new.search("a")
    assert_equal({ docs: [], total: 0 }, result)
  end
  test "fetch_work returns parsed hash" do
    stub_request(:get, "https://openlibrary.org/works/OL45804W.json")
      .to_return(
        status: 200,
        body: '{"title": "Harry Potter", "description": "A wizard story"}',
        headers: { "Content-Type" => "application/json" }
      )

    result = OpenLibraryClient.new.fetch_work("OL45804W")
    assert result.key?("title")
    assert result.key?("description")
  end

  test "fetch_work returns nil on Faraday error" do
    stub_request(:get, "https://openlibrary.org/works/OL45804W.json")
      .to_raise(Faraday::TimeoutError)

    result = OpenLibraryClient.new.fetch_work("OL45804W")
    assert_nil result
  end

  test "fetch_editions returns parsed hash with entries" do
    stub_request(:get, "https://openlibrary.org/works/OL45804W/editions.json")
      .to_return(
        status: 200,
        body: '{"entries": [{"key": "/books/OL123M", "publishers": ["Scholastic"]}]}',
        headers: { "Content-Type" => "application/json" }
      )

    result = OpenLibraryClient.new.fetch_editions("OL45804W")
    assert result.key?("entries")
    assert_not_empty result["entries"]
  end

  test "fetch_editions returns nil on Faraday error" do
    stub_request(:get, "https://openlibrary.org/works/OL45804W/editions.json")
      .to_raise(Faraday::TimeoutError)

    result = OpenLibraryClient.new.fetch_editions("OL45804W")
    assert_nil result
  end

  test "fetch_editions follows pagination for works with more than 50 editions" do
    # Reproduces a real case (Dune, work OL893414W, 160 editions): the
    # target edition was on page 2, entirely missed when only page 1 was
    # fetched.
    stub_request(:get, "https://openlibrary.org/works/OL893414W/editions.json")
      .to_return(
        status: 200,
        body: {
          entries: [ { key: "/books/OL1M" } ],
          size: 2,
          links: { next: "/works/OL893414W/editions.json?offset=1" }
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
    stub_request(:get, "https://openlibrary.org/works/OL893414W/editions.json?offset=1")
      .to_return(
        status: 200,
        body: { entries: [ { key: "/books/OL22597282M", isbn_13: [ "9780441172719" ] } ], size: 2 }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    result = OpenLibraryClient.new.fetch_editions("OL893414W")

    assert_equal 2, result["entries"].size
    assert_includes result["entries"].map { |e| e["key"] }, "/books/OL22597282M"
  end

  test "fetch_by_isbn returns parsed hash on direct 200" do
    stub_request(:get, "https://openlibrary.org/isbn/9780134757599.json")
      .to_return(status: 200, body: '{"title": "Refactoring", "works": [{"key": "/works/OL45804W"}]}',
        headers: { "Content-Type" => "application/json" })

    result = OpenLibraryClient.new.fetch_by_isbn("9780134757599")
    assert_equal "Refactoring", result["title"]
  end

  test "fetch_by_isbn follows the 302 redirect Open Library actually returns" do
    stub_request(:get, "https://openlibrary.org/isbn/9781982143619.json")
      .to_return(status: 302, headers: { "Location" => "https://openlibrary.org/books/OL29844304M.json" })
    stub_request(:get, "https://openlibrary.org/books/OL29844304M.json")
      .to_return(status: 200, body: '{"title": "Halo : Shadows of Reach", "works": [{"key": "/works/OL21884664W"}]}',
        headers: { "Content-Type" => "application/json" })

    result = OpenLibraryClient.new.fetch_by_isbn("9781982143619")
    assert_equal "Halo : Shadows of Reach", result["title"]
  end

  test "fetch_by_isbn returns nil on 404" do
    stub_request(:get, "https://openlibrary.org/isbn/0000000000.json")
      .to_return(status: 404, body: "")

    result = OpenLibraryClient.new.fetch_by_isbn("0000000000")
    assert_nil result
  end

  test "fetch_by_isbn returns nil on Faraday error" do
    stub_request(:get, "https://openlibrary.org/isbn/9780134757599.json")
      .to_raise(Faraday::TimeoutError)

    result = OpenLibraryClient.new.fetch_by_isbn("9780134757599")
    assert_nil result
  end

  test "fetch_author returns parsed hash" do
    stub_request(:get, "https://openlibrary.org/authors/OL1601536A.json")
      .to_return(status: 200, body: '{"name": "Troy Denning"}', headers: { "Content-Type" => "application/json" })

    result = OpenLibraryClient.new.fetch_author("OL1601536A")
    assert_equal "Troy Denning", result["name"]
  end

  test "fetch_author returns nil on Faraday error" do
    stub_request(:get, "https://openlibrary.org/authors/OL1601536A.json")
      .to_raise(Faraday::TimeoutError)

    result = OpenLibraryClient.new.fetch_author("OL1601536A")
    assert_nil result
  end
end
