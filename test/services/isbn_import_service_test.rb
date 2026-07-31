require "test_helper"

class IsbnImportServiceTest < ActiveSupport::TestCase
  def setup
    Rails.cache.clear
  end

  test "creates Book and matching BookEdition on remote hit" do
    stub_request(:get, "https://openlibrary.org/isbn/9780134757599.json")
      .to_return(
        status: 200,
        body: { title: "Refactoring", works: [ { key: "/works/OL45804W" } ], by_statement: "Martin Fowler" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
    stub_request(:get, "https://openlibrary.org/works/OL45804W.json")
      .to_return(
        status: 200,
        body: { title: "Refactoring", description: "", subjects: [] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
    stub_request(:get, "https://openlibrary.org/works/OL45804W/editions.json")
      .to_return(
        status: 200,
        body: { entries: [ { key: "/books/OL1M", isbn_13: [ "9780134757599" ], title: "Refactoring" } ] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    assert_difference [ "Book.count", "BookEdition.count" ], 1 do
      result = IsbnImportService.new("9780134757599").call
      assert_equal "9780134757599", result.isbn
    end
  end

  test "resolves author via the authors endpoint when by_statement is missing" do
    # This is the real shape Open Library returns for most editions: a 302
    # redirect (not a direct 200) and no "by_statement" field, only an
    # unresolved author key. Reproduces a real ISBN (Halo: Shadows of Reach)
    # that silently failed before both of these were handled.
    stub_request(:get, "https://openlibrary.org/isbn/9781982143619.json")
      .to_return(status: 302, headers: { "Location" => "https://openlibrary.org/books/OL29844304M.json" })
    stub_request(:get, "https://openlibrary.org/books/OL29844304M.json")
      .to_return(
        status: 200,
        body: {
          title: "Halo : Shadows of Reach",
          works: [ { key: "/works/OL21884664W" } ],
          authors: [ { key: "/authors/OL1601536A" } ]
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
    stub_request(:get, "https://openlibrary.org/authors/OL1601536A.json")
      .to_return(status: 200, body: { name: "Troy Denning" }.to_json, headers: { "Content-Type" => "application/json" })
    stub_request(:get, "https://openlibrary.org/works/OL21884664W.json")
      .to_return(status: 200, body: { title: "Halo : Shadows of Reach", description: "", subjects: [] }.to_json,
        headers: { "Content-Type" => "application/json" })
    stub_request(:get, "https://openlibrary.org/works/OL21884664W/editions.json")
      .to_return(
        status: 200,
        body: { entries: [ { key: "/books/OL29844304M", isbn_13: [ "9781982143619" ], title: "Halo : Shadows of Reach" } ] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    result = IsbnImportService.new("9781982143619").call

    assert_equal "9781982143619", result.isbn
    assert_equal "Troy Denning", result.book.author
  end

  test "finds an edition beyond the first page of a work's editions list" do
    # Reproduces a real ISBN (Dune, 9780441172719): the work (OL893414W) has
    # 160 editions on Open Library, and the matching edition (OL22597282M)
    # is at overall position 90 — past the first 50-entry page. Without
    # following pagination, mirror_editions never creates a local
    # BookEdition for it and the ISBN is reported as not found.
    stub_request(:get, "https://openlibrary.org/isbn/9780441172719.json")
      .to_return(status: 302, headers: { "Location" => "https://openlibrary.org/books/OL22597282M.json" })
    stub_request(:get, "https://openlibrary.org/books/OL22597282M.json")
      .to_return(
        status: 200,
        body: { title: "Dune", works: [ { key: "/works/OL893414W" } ], by_statement: "Frank Herbert." }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
    stub_request(:get, "https://openlibrary.org/works/OL893414W.json")
      .to_return(status: 200, body: { title: "Dune", description: "", subjects: [] }.to_json,
        headers: { "Content-Type" => "application/json" })
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
        body: { entries: [ { key: "/books/OL22597282M", isbn_13: [ "9780441172719" ], title: "Dune" } ] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    result = IsbnImportService.new("9780441172719").call

    assert_equal "9780441172719", result.isbn
    assert_equal "Dune", result.book.title
  end

  test "resolves author via the work record when the edition has no author info at all" do
    # Reproduces a real ISBN (The Hunger Games, 9780439023481): the edition
    # record has neither "by_statement" nor an "authors" array — author only
    # exists on the Work record, nested as authors[0]["author"]["key"]
    # (not authors[0]["key"], which is the edition-level shape).
    stub_request(:get, "https://openlibrary.org/isbn/9780439023481.json")
      .to_return(status: 302, headers: { "Location" => "https://openlibrary.org/books/OL37079411M.json" })
    stub_request(:get, "https://openlibrary.org/books/OL37079411M.json")
      .to_return(
        status: 200,
        body: { title: "The Hunger Games", works: [ { key: "/works/OL5735363W" } ] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
    stub_request(:get, "https://openlibrary.org/works/OL5735363W.json")
      .to_return(
        status: 200,
        body: {
          title: "The Hunger Games",
          description: "Katniss Everdeen...",
          subjects: [],
          authors: [ { author: { key: "/authors/OL1394359A" } } ]
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
    stub_request(:get, "https://openlibrary.org/authors/OL1394359A.json")
      .to_return(status: 200, body: { name: "Suzanne Collins" }.to_json, headers: { "Content-Type" => "application/json" })
    stub_request(:get, "https://openlibrary.org/works/OL5735363W/editions.json")
      .to_return(
        status: 200,
        body: { entries: [ { key: "/books/OL37079411M", isbn_13: [ "9780439023481" ], title: "The Hunger Games" } ] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    result = IsbnImportService.new("9780439023481").call

    assert_equal "9780439023481", result.isbn
    assert_equal "Suzanne Collins", result.book.author
    assert_equal "Katniss Everdeen...", result.book.description
  end

  test "returns nil when ISBN is not found locally or on Open Library" do
    stub_request(:get, "https://openlibrary.org/isbn/0000000000.json")
      .to_return(status: 404, body: "")

    assert_no_difference [ "Book.count", "BookEdition.count" ] do
      assert_nil IsbnImportService.new("0000000000").call
    end
  end

  test "quick-adding the same ISBN twice does not create a duplicate BookEdition" do
    stub_request(:get, "https://openlibrary.org/isbn/9780134757599.json")
      .to_return(
        status: 200,
        body: { title: "Refactoring", works: [ { key: "/works/OL45804W" } ], by_statement: "Martin Fowler" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
    stub_request(:get, "https://openlibrary.org/works/OL45804W.json")
      .to_return(
        status: 200,
        body: { title: "Refactoring", description: "", subjects: [] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
    stub_request(:get, "https://openlibrary.org/works/OL45804W/editions.json")
      .to_return(
        status: 200,
        body: { entries: [ { key: "/books/OL1M", isbn_13: [ "9780134757599" ], title: "Refactoring" } ] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    first = IsbnImportService.new("9780134757599").call
    assert_no_difference "BookEdition.count" do
      second = IsbnImportService.new("9780134757599").call
      assert_equal first, second
    end

    assert_requested :get, "https://openlibrary.org/isbn/9780134757599.json", times: 1
  end
end
