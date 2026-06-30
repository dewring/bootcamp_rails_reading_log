require "test_helper"

class OpenLibraryClientTest < ActiveSupport::TestCase
  test "search returns docs array" do
    stub_request(:get, "https://openlibrary.org/search.json")
      .with(query: { q: "Harry Potter" })
      .to_return(
        status: 200,
        body: '{"docs": [{"key": "/works/OL82563W", "title": "Harry Potter"}]}',
        headers: { "Content-Type" => "application/json" }
      )

    result = OpenLibraryClient.new.search("Harry Potter")
    assert_not_empty result
    assert result.first.key?("key")
  end

  test "search returns empty array on Faraday error" do
    stub_request(:get, "https://openlibrary.org/search.json")
      .with(query: { q: "anything" })
      .to_raise(Faraday::TimeoutError)

    result = OpenLibraryClient.new.search("anything")
    assert_equal [], result
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
end
