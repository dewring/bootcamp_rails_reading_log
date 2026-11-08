require "application_system_test_case"

class BookClubLiveUpdatesTest < ApplicationSystemTestCase
  include Warden::Test::Helpers
  include ActiveJob::TestHelper

  # WebSocket workers and the second browser session must see committed records.
  self.use_transactional_tests = false

  def queue_adapter_for_test
    ActiveJob::QueueAdapters::TestAdapter.new
  end

  setup do
    Warden.test_mode!
    @owner = users(:leika)
    @member = users(:jaina)
    @first_book = Book.create!(title: "Live first pick", author: "First Author", total_pages: 200)
    @next_book = Book.create!(title: "Live next pick", author: "Next Author", total_pages: 300)
    @club = BookClub.create!(name: "Live browser circle", current_book: @first_book)
    @club.book_club_memberships.create!(user: @owner, role: "owner")
    @club.book_club_memberships.create!(user: @member, role: "member")
    @own_post = @club.club_messages.create!(user: @member, body: "My saved thought")
    @other_post = @club.club_messages.create!(user: @owner, body: "The owner's question")
    8.times do |index|
      @club.club_messages.create!(user: @owner, body: "Discussion context #{index}")
    end
    Capybara.using_session(:club_owner) do
      login_as @owner, scope: :user
      visit book_club_path(@club)
      assert_selector "#owner-controls"
    end
    login_as @member, scope: :user
  end

  teardown do
    Capybara.reset_sessions!
    Warden.test_reset!
    server = ActionCable.server
    executor = server.worker_pool.executor
    executor.shutdown
    assert executor.wait_for_termination(5)
    server.restart
    Noticed::Event.where(record: @club).destroy_all
    @club.destroy!
    @first_book.destroy!
    @next_book.destroy!
  end

  test "owner pick and deadline changes reach Discussion without replacing drafts or moving scroll" do
    visit book_club_club_messages_path(@club)
    assert_selector "turbo-cable-stream-source[connected]", visible: :all
    assert_selector "#current_pick_book_club_#{@club.id} h2", text: @first_book.title
    fill_in "Your discussion post", with: "Unsent new post"
    within "#club_message_#{@own_post.id}" do
      click_button "Edit", exact: true
      fill_in "Edit your message", with: "Unsent edit"
    end
    within "#club_message_#{@other_post.id}" do
      find("[data-club-replies-target='toggle']").click
      fill_in "Your reply", with: "Unsent reply"
    end
    page.execute_script(<<~JS)
      window.savedDiscussionDocument = document.documentElement
      window.savedDiscussionInputs = Array.from(document.querySelectorAll('textarea')).filter(input => input.value.startsWith('Unsent'))
      window.scrollTo(0, 600)
    JS
    @scroll_position = page.evaluate_script("window.scrollY")
    assert_operator @scroll_position, :>, 0

    update_pick_from_owner(book_title: @next_book.title, deadline: "2026-12-20")
    assert_selector "#current_pick_book_club_#{@club.id} h2", text: @next_book.title
    assert_selector "#current_pick_book_club_#{@club.id} time[datetime='2026-12-20']"
    assert_discussion_drafts_and_scroll

    update_pick_from_owner(deadline: "2026-12-25")
    assert_selector "#current_pick_book_club_#{@club.id} time[datetime='2026-12-25']"
    assert_discussion_drafts_and_scroll

    update_pick_from_owner(book_title: "", deadline: "")
    assert_selector "#current_pick_book_club_#{@club.id}", text: "No current pick yet."
    assert_selector "#current_pick_book_club_#{@club.id}", text: "No reading deadline"
    assert_discussion_drafts_and_scroll
  end

  test "owner pick changes automatically refresh Overview and Leaderboard in other sessions" do
    ReadingSession.create!(user: @owner, book: @first_book, read_on: Date.current, pages_read: 10)
    ReadingSession.create!(user: @member, book: @first_book, read_on: Date.current, pages_read: 15)
    ReadingSession.create!(user: @owner, book: @next_book, read_on: Date.current, pages_read: 20)
    ReadingSession.create!(user: @member, book: @next_book, read_on: Date.current, pages_read: 30)
    visit book_club_path(@club)
    assert_selector "turbo-cable-stream-source[connected]", visible: :all
    assert_selector "#current_pick_book_club_#{@club.id} h2", text: @first_book.title
    assert_no_selector ".book-club-detail-page a", text: "Refresh"
    Capybara.using_session(:club_leaderboard) do
      login_as @member, scope: :user
      visit book_club_leaderboard_path(@club)
      assert_selector "turbo-cable-stream-source[connected]", visible: :all
      assert_selector ".book-club-reading-rail-book strong", text: @first_book.title
      assert_selector ".book-club-ranking-row--current .book-club-ranking-pages", text: "15", exact_text: true
      assert_no_selector ".book-club-detail-page a", text: "Refresh"
    end

    update_pick_from_owner(book_title: @next_book.title, deadline: "2026-12-20")

    assert_selector "#current_pick_book_club_#{@club.id} h2", text: @next_book.title
    assert_selector "#current_pick_book_club_#{@club.id} time[datetime='2026-12-20']"
    assert_current_path book_club_path(@club)
    Capybara.using_session(:club_leaderboard) do
      assert_selector ".book-club-reading-rail-book strong", text: @next_book.title
      assert_selector ".book-club-ranking-row--current .book-club-ranking-pages", text: "30", exact_text: true
      assert_selector ".book-club-ranking-row--current strong", text: @member.nickname
      assert_current_path book_club_leaderboard_path(@club)
    end
  end

  private

  def update_pick_from_owner(book_title: nil, deadline:)
    perform_enqueued_jobs(only: [ BookClubCurrentPickJob, BookClubLeaderboardJob ]) do
      Capybara.using_session(:club_owner) do
        within "#owner-controls" do
          unless book_title.nil?
            fill_in "Current pick", with: book_title
            find("[role='option']", text: book_title).click if book_title.present?
          end
          fill_in "Reading deadline", with: deadline.present? ? Date.iso8601(deadline) : ""
          click_button "Save changes"
        end
        assert_selector ".flash-notification", text: "Book club updated."
        if deadline.present?
          assert_selector "#current_pick_book_club_#{@club.id} time[datetime='#{deadline}']"
          assert_equal deadline, @club.reload.reading_deadline&.iso8601
        else
          assert_selector "#current_pick_book_club_#{@club.id}", text: "No reading deadline"
          assert_nil @club.reload.reading_deadline
        end
      end
    end
  end

  def assert_discussion_drafts_and_scroll
    assert_in_delta @scroll_position, page.evaluate_script("window.scrollY"), 1
    assert page.evaluate_script("document.documentElement === window.savedDiscussionDocument")
    assert page.evaluate_script("window.savedDiscussionInputs.length === 3 && window.savedDiscussionInputs.every(input => input.isConnected)")
    assert_field "Your discussion post", with: "Unsent new post"
    assert_field "Edit your message", with: "Unsent edit"
    assert_field "Your reply", with: "Unsent reply"
    assert_current_path book_club_club_messages_path(@club)
  end
end
