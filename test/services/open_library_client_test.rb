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
end
