require "test_helper"
require "tmpdir"

class DevelopmentReadingScenarioGenresTest < ActionDispatch::IntegrationTest
  setup do
    @directory = Pathname.new(Dir.mktmpdir("booknook-genres-"))
    @store = DevelopmentReadingScenarioManifest.new(path: @directory.join("manifest.json"))
    @genres = Genre::GENRES.to_h { |name| [ name, Genre.find_or_create_by!(name: name) ] }
    @books = Genre::GENRES.each_with_index.to_h do |name, index|
      book = Book.create!(title: "Genre demo #{name}", author: "Demo Author", ol_work_key: "/works/OL#{400_000 + index}W", subjects: [ name ])
      [ name, book ]
    end
    with_scenario do |manifest|
      manifest["bootstrap"] = { "records" => { "genres" => @genres.transform_values { |genre| { "id" => genre.id } } } }
      manifest["catalog"] = { "records" => @books.values.to_h { |book| [ book.ol_work_key, { "book" => { "id" => book.id } } ] } }
      @store.save_scenario(manifest)
    end
  end

  teardown do
    FileUtils.remove_entry(@directory)
  end

  test "all twelve genre filters return books linked from matching subjects" do
    result = seed_genres
    assert_equal "complete", result.dig("book_genres", "status")

    @books.each do |name, book|
      get books_path, params: { genre: name }, as: :json

      assert_response :success
      found = response.parsed_body.fetch("books")
      assert_includes found.map { |entry| entry.fetch("id") }, book.id
      assert found.all? { |entry| entry.fetch("genres").any? { |genre| genre.fetch("name") == name } }
    end
  end

  test "subject aliases match genres without classifying nonfiction as fiction or guessing unknown subjects" do
    @books.fetch("Non-Fiction").update!(subjects: [ "Nonfiction" ])
    @books.fetch("Science-Fiction").update!(subjects: [ "SCIENCE FICTION" ])
    @books.fetch("Biography").update!(subjects: [ "Autobiographies" ])
    @books.fetch("Self-Help").update!(subjects: [ "SELF HELP / Personal Growth" ])
    @books.fetch("Poetry").update!(subjects: [ "Love poems" ])
    @books.fetch("History").update!(subjects: [ "Unknown topic" ])

    seed_genres

    assert_equal [ "Non-Fiction" ], @books.fetch("Non-Fiction").genres.pluck(:name)
    assert_equal [ "Fiction", "Science-Fiction" ], @books.fetch("Science-Fiction").genres.order(:name).pluck(:name)
    [ "Biography", "Self-Help", "Poetry" ].each do |name|
      assert_equal [ name ], @books.fetch(name).genres.pluck(:name)
    end
    assert_empty @books.fetch("History").genres
  end

  test "replay preserves existing links book attributes ids and timestamps without duplicates" do
    existing = BookGenre.create!(book: @books.fetch("Mystery"), genre: @genres.fetch("Poetry"))
    original = existing.attributes
    books_before = Book.order(:id).map(&:attributes)
    seed_genres
    links_before = BookGenre.order(:id).map(&:attributes)

    seed_genres

    assert_equal original, existing.reload.attributes
    assert_equal books_before, Book.order(:id).map(&:attributes)
    assert_equal links_before, BookGenre.order(:id).map(&:attributes)
  end

  test "a failed manifest checkpoint resumes without duplicate links" do
    initial = BookGenre.count
    rename = File.method(:rename)
    File.stub(:rename, ->(source, destination) {
      if Pathname.new(destination) == @directory.join("manifest.json") && BookGenre.count > initial
        raise IOError, "Interrupted after genre insertion"
      end
      rename.call(source, destination)
    }) do
      assert_raises(IOError) { seed_genres }
    end
    before = BookGenre.order(:id).map(&:attributes)

    assert_equal "complete", seed_genres.dig("book_genres", "status")
    assert_equal before, BookGenre.order(:id).map(&:attributes)
  end

  test "replay reports a deleted link and reuses an existing replacement for the same pair" do
    first = seed_genres.fetch("book_genres")
    mystery = @books.fetch("Mystery")
    deleted = mystery.book_genres.sole
    deleted.destroy!
    poetry = @books.fetch("Poetry")
    poetry.book_genres.sole.destroy!
    replacement = BookGenre.create!(book: poetry, genre: @genres.fetch("Poetry"))
    original = BookGenre.order(:id).map(&:attributes)

    assert_no_difference "BookGenre.count" do
      result = seed_genres.fetch("book_genres")
      skipped = result.dig("records", "#{mystery.ol_work_key}/Mystery")
      assert_equal "skipped", skipped.fetch("result")
      assert_equal "recorded_genre_link_missing", skipped.fetch("reason")
      assert_equal deleted.id, skipped.fetch("id")
      reused = result.dig("records", "#{poetry.ol_work_key}/Poetry")
      assert_equal replacement.id, reused.fetch("id")
      assert_equal "reused", reused.fetch("origin")
      assert_equal first.fetch("actual_count") - 1, result.fetch("actual_count")
      assert_equal result, seed_genres.fetch("book_genres")
    end
    assert_equal original, BookGenre.order(:id).map(&:attributes)
  end

  private

  def with_scenario
    Rails.stub(:env, "development".inquiry) do
      yield @store.prepare_scenario(snapshot_id: "genre-test")
    end
  end

  def seed_genres
    with_scenario do |manifest|
      DevelopmentReadingScenarioGenres.new(manifest: manifest, scenario_manifest: @store).seed_genres
    end
  end
end
