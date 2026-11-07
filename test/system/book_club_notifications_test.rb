require "application_system_test_case"

class BookClubNotificationsTest < ApplicationSystemTestCase
  include Warden::Test::Helpers
  include ActiveJob::TestHelper

  def queue_adapter_for_test
    ActiveJob::QueueAdapters::TestAdapter.new
  end

  teardown do
    Warden.test_reset!
  end

  test "a returning member opens a saved leader notification and sees their own ranking highlight" do
    owner = users(:leika)
    leader = users(:jaina)
    book = Book.create!(title: "Browser leaderboard book", author: "An Author")
    club = BookClub.create!(name: "Browser leaderboard circle", current_book: book)
    club.book_club_memberships.create!(user: owner, role: "owner")
    club.book_club_memberships.create!(user: leader, role: "member")
    ReadingSession.create!(user: owner, book: book, read_on: Date.current, pages_read: 10)
    BookClubLeaderboardJob.perform_now(club.id)
    ReadingSession.create!(user: leader, book: book, read_on: Date.current, pages_read: 20)
    BookClubLeaderboardJob.perform_now(club.id)
    Warden.test_mode!
    login_as owner, scope: :user

    visit books_path
    find("button[aria-label='Notifications']").hover
    assert_selector "#notifications_dropdown", visible: true
    within "#notifications_dropdown" do
      find("a[href='#{book_club_leaderboard_path(club)}']",
        text: "#{leader.nickname} is now first in Browser leaderboard circle for Browser leaderboard book.").click
    end

    assert_current_path book_club_leaderboard_path(club)
    assert_selector ".book-club-ranking-row:first-child strong", text: leader.nickname
    assert_selector ".book-club-ranking-row--current strong", text: owner.nickname
    assert_selector ".book-club-ranking-row--current", count: 1
  end
end
