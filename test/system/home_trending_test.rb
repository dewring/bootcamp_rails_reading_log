require "application_system_test_case"

class HomeTrendingTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  setup do
    Warden.test_mode!
    login_as users(:leika), scope: :user
  end

  teardown do
    Warden.test_reset!
  end

  test "plain trending cards precede other shelves and keep their order until a new page load on desktop and mobile" do
    first = Book.create!(title: "Trending leader", author: "Test author")
    others = 2.times.map { |index| Book.create!(title: "Trending peer #{index}", author: "Test author") }
    [ first, *others ].each do |book|
      book.reactions.create!(user: users(:leika), kind: "dislike", updated_at: 1.hour.ago)
    end
    first.reactions.create!(user: users(:jaina), kind: "love", updated_at: 1.hour.ago)

    visit root_path

    within ".home-trending" do
      assert_text "Trending"
      assert_selector ".book-card", count: 3
      assert_no_selector ".reaction-panel, .home-trending-rank, .home-trending-score, time"
      assert_no_link "View All"
      assert_no_button "Refresh"
    end
    assert_equal [ "Trending", "Most Read", "New Books" ], all("section.home-section > header > h2").map(&:text)
    original_links = all(".home-trending .book-card").map { |card| card[:href] }
    assert_equal first.title, find(".home-trending .book-card:first-child .book-title").text
    first.reactions.destroy_all
    assert_equal original_links, all(".home-trending .book-card").map { |card| card[:href] }

    page.current_window.resize_to(390, 844)
    assert_selector ".home-trending .book-card", count: 3
    page.execute_script(<<~JS)
      const row = document.querySelector('.home-trending .book-row')
      row.scrollLeft = row.scrollWidth
    JS
    assert page.evaluate_script(<<~JS), "The final Trending card must be reachable inside the horizontal row"
      (() => {
        const row = document.querySelector('.home-trending .book-row')
        const lastCard = row.lastElementChild
        return row.scrollLeft > 0 && lastCard.getBoundingClientRect().right <= row.getBoundingClientRect().right + 1
      })()
    JS
    within ".home-trending" do
      assert_link others.last.title
    end

    visit root_path

    within ".home-trending" do
      assert_no_link first.title
      assert_selector ".book-card", count: 2
    end
  ensure
    page.current_window.resize_to(1400, 1000)
  end
end
