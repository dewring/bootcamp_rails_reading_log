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

  test "rendering count broadcasts preserves ranks and card order until a new page load on desktop and mobile" do
    first = Book.create!(title: "Trending leader", author: "Test author")
    others = 2.times.map { |index| Book.create!(title: "Trending peer #{index}", author: "Test author") }
    [ first, *others ].each do |book|
      book.reactions.create!(user: users(:leika), kind: "dislike", updated_at: 1.hour.ago)
    end
    first.reactions.create!(user: users(:jaina), kind: "love", updated_at: 1.hour.ago)

    visit root_path

    within ".home-trending" do
      assert_text "Trending"
      assert_selector ".home-trending-card", count: 3
      assert_selector ".home-trending-rank", text: "Rank 2", count: 2
      assert_no_link "View All"
      assert_no_button "Refresh"
    end
    original_ids = all(".home-trending-card").map { |card| card[:id] }
    first.reactions.destroy_all
    streams = capture_turbo_stream_broadcasts("book_reactions_#{first.id}") do
      ReactionTotalsJob.perform_now("Book", first.id)
    end
    page.execute_script("document.body.insertAdjacentHTML('beforeend', arguments[0])", streams.first.to_html)

    within "#trending_book_#{first.id}" do
      assert_no_selector ".reaction-pills [data-kind='love']:not([hidden])"
      assert_no_selector ".reaction-pills [data-kind='dislike']:not([hidden])"
      assert_text "Rank 1"
      assert_text "7-day reactions: 2"
    end
    assert_equal original_ids, all(".home-trending-card").map { |card| card[:id] }

    page.current_window.resize_to(390, 844)
    assert_selector ".home-trending-card", count: 3
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

    assert_no_selector "#trending_book_#{first.id}"
    assert_selector ".home-trending-rank", text: "Rank 1", count: 2
  ensure
    page.current_window.resize_to(1400, 1000)
  end
end
