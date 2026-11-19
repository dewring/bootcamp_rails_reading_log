require "test_helper"

class BooksHelperTest < ActionView::TestCase
  test "book_cover_fallback_tone returns the same tone for the same seed" do
    assert_equal book_cover_fallback_tone(42), book_cover_fallback_tone(42)
    assert_equal book_cover_fallback_tone("/works/OL1W"), book_cover_fallback_tone("/works/OL1W")
  end

  test "book_cover_fallback_tone stays within the six pastel tones" do
    tones = (1..200).map { |seed| book_cover_fallback_tone(seed) }

    assert tones.all? { |tone| tone.between?(0, BooksHelper::BOOK_COVER_FALLBACK_TONE_COUNT - 1) }
    assert_equal BooksHelper::BOOK_COVER_FALLBACK_TONE_COUNT, tones.uniq.size
  end

  test "book_cover_fallback_initial returns the first letter or digit in upper case" do
    assert_equal "A", book_cover_fallback_initial("a gentle reminder")
    assert_equal "1", book_cover_fallback_initial("101 Essays")
    assert_equal "I", book_cover_fallback_initial("\"I Don't Love You Anymore\"")
  end

  test "book_description_excerpt removes the source credit and Markdown emphasis" do
    book = Book.new(description: "**Before It Ends with Us**, it started with Atlas. ([source](https://example.com))")

    assert_equal "Before It Ends with Us, it started with Atlas.", book_description_excerpt(book)
  end

  test "book_description_excerpt shortens long descriptions at a word boundary" do
    book = Book.new(description: "word " * 60)

    excerpt = book_description_excerpt(book, length: 40)

    assert_operator excerpt.length, :<=, 40
    assert excerpt.end_with?("word...")
  end

  test "small fallback cover shows only the title initial" do
    render partial: "books/cover_fallback",
           locals: { title: "A Gentle Reminder", author: "Bianca Sparacino", seed: 1, size: :small }

    assert_select ".book-cover-fallback--small[role='img'][aria-label='Cover of A Gentle Reminder']" do
      assert_select ".book-cover-fallback-initial", text: "A"
      assert_select ".book-cover-fallback-title", count: 0
      assert_select ".book-cover-fallback-author", count: 0
    end
  end

  test "fallback cover omits the author line when the author is blank" do
    render partial: "books/cover_fallback",
           locals: { title: "Untitled Notes", author: nil, seed: 1, size: :medium }

    assert_select ".book-cover-fallback-title", text: "Untitled Notes"
    assert_select ".book-cover-fallback-author", count: 0
  end
end
