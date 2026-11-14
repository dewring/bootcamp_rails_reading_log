require "application_system_test_case"

class EditionCardLayoutTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  setup do
    Warden.test_mode!
    login_as users(:leika), scope: :user
  end

  teardown do
    Warden.test_reset!
  end

  test "long edition text truncates within cards across desktop tablet and mobile layouts" do
    book = Book.create!(title: "Edition layout", author: "An author with a very long name " * 8)
    3.times do |index|
      book.book_editions.create!(
        ol_edition_key: "/books/LAYOUT#{index}M",
        title: "A very long edition title " * 12,
        publisher: "A publisher with a very long name " * 8,
        publish_year: 2026,
        language: "English"
      )
    end

    { 1400 => 3, 1024 => 3, 800 => 2, 390 => 1 }.each do |width, expected_columns|
      page.current_window.resize_to(width, 1000)
      visit book_path(book)
      # The browser suite blocks CDN requests; reuse the local Pico sizing rules.
      page.execute_script(<<~JS, Rails.root.join("test/fixtures/stylesheets/pico_navigation.css").read)
        const style = document.createElement("style")
        style.nonce = document.querySelector('meta[name="csp-nonce"]').content
        style.textContent = arguments[0]
        document.head.insertBefore(style, document.querySelector('link[data-turbo-track="reload"]'))
      JS
      find(".book-detail-edition-grid").scroll_to(:center)
      cards = all(".book-detail-edition-card", count: 3)
      columns = find(".book-detail-edition-grid").style("grid-template-columns").fetch("grid-template-columns").split.size
      assert_equal expected_columns, columns

      cards.each do |card|
        bounds = card.evaluate_script("this.getBoundingClientRect().toJSON()")
        cover = card.find(".book-detail-edition-cover").evaluate_script("this.getBoundingClientRect().toJSON()")
        assert_operator cover.fetch("width"), :>=, 78
        assert_operator cover.fetch("right"), :<, bounds.fetch("right")

        card.all("h3, p, small", count: 3).each do |text|
          geometry = text.evaluate_script("({right: this.getBoundingClientRect().right, client: this.clientWidth, scroll: this.scrollWidth})")
          assert_operator geometry.fetch("right"), :<=, bounds.fetch("right"), "Text escapes its card at #{width}px"
          assert_operator geometry.fetch("client"), :>, 0
          assert_operator geometry.fetch("scroll"), :>, geometry.fetch("client")
          assert_equal "ellipsis", text.style("text-overflow").fetch("text-overflow")
        end
      end
      assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, page.evaluate_script("window.innerWidth")
    end
  end
end
