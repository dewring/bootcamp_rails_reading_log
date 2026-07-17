require "test_helper"

class BadgeAwardJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "does not award first_session badge when user has no reading sessions" do
    BadgeAwardJob.new.perform(users(:jaina))
    badge = Badge.find_by(badge_type: "first_session")

    assert_not UserBadge.exists?(user: users(:jaina), badge: badge)
  end

  test "awards first_session badge after user logs one reading session" do
    ReadingSession.create!(user: users(:jaina), book: books(:refactoring), read_on: Date.today, pages_read: 50)
    BadgeAwardJob.new.perform(users(:jaina))
    badge = Badge.find_by(badge_type: "first_session")

    assert UserBadge.exists?(user: users(:jaina), badge: badge)
  end

  test "does not create a duplicate UserBadge when run twice for the same user" do
    ReadingSession.create!(user: users(:jaina), book: books(:refactoring), read_on: Date.today, pages_read: 50)
    BadgeAwardJob.new.perform(users(:jaina))

    assert_no_difference "UserBadge.count" do
      BadgeAwardJob.new.perform(users(:jaina))
    end
  end

  test "awarded UserBadge is linked to the correct badge and user" do
    working_user = users(:jaina)
    no_working_user= users(:leika)

    ReadingSession.create!(user: working_user, book: books(:refactoring), read_on: Date.today, pages_read: 50)
    BadgeAwardJob.new.perform(working_user)
    badge = Badge.find_by(badge_type: "first_session")

    assert UserBadge.exists?(user: working_user, badge: badge)
    assert_not UserBadge.exists?(user: no_working_user, badge: badge)
  end

  test "does not award bookworm badge when user has fewer than 5 finished books" do
    4.times { create_finished_book_for(users(:jaina)) }

    BadgeAwardJob.new.perform(users(:jaina))
    badge = Badge.find_by(badge_type: "bookworm")

    assert_not UserBadge.exists?(user: users(:jaina), badge: badge)
  end

  test "awards bookworm badge when user has exactly 5 finished books" do
    5.times { create_finished_book_for(users(:jaina)) }

    BadgeAwardJob.new.perform(users(:jaina))
    badge = Badge.find_by(badge_type: "bookworm")

    assert UserBadge.exists?(user: users(:jaina), badge: badge)
  end

  test "does not count books with a non-finished status toward the bookworm threshold" do
    4.times { create_finished_book_for(users(:jaina)) }

    book = Book.create!(title: "Book #{SecureRandom.hex(4)}", author: "Test Author")
    UserBook.create!(user: users(:jaina), book: book, status: "reading")

    BadgeAwardJob.new.perform(users(:jaina))
    badge = Badge.find_by(badge_type: "bookworm")

    assert_not UserBadge.exists?(user: users(:jaina), badge: badge)
  end

  test "bookworm badge is linked to the correct user, not another user" do
    5.times { create_finished_book_for(users(:jaina)) }

    BadgeAwardJob.new.perform(users(:jaina))
    badge = Badge.find_by(badge_type: "bookworm")


    assert UserBadge.exists?(user: users(:jaina), badge: badge)
    assert_not UserBadge.exists?(user: users(:leika), badge: badge)
  end

private

  def create_finished_book_for(user)
    book = Book.create!(title: "Book #{SecureRandom.hex(4)}", author: "Test Author")
    UserBook.create!(user: user, book: book, status: "finished")
  end
end
