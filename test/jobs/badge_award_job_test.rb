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

  test "does not award challenge_complete badge when user has no completed challenge" do
    BadgeAwardJob.new.perform(users(:jaina))
    badge = Badge.find_by(badge_type: "challenge_complete")

    assert_not UserBadge.exists?(user: users(:jaina), badge: badge)
  end

  test "awards challenge_complete badge when user has a completed challenge" do
    create_challenge_and_userchallenge(users(:jaina))

    BadgeAwardJob.new.perform(users(:jaina))
    badge = Badge.find_by(badge_type: "challenge_complete")

    assert UserBadge.exists?(user: users(:jaina), badge: badge)
  end

  test "does not count a challenge with an in_progress or failed status" do
    in_progress_challenge = Challenge.create!(
      title: "reading book total 1000 pages",
      goal_type: "books_total",
      goal_value: 1000,
      starts_at: 2.week.ago,
      ends_at: Date.today
    )
    UserChallenge.create!(user: users(:jaina), challenge: in_progress_challenge, status: "in_progress")

    failed_challenge = Challenge.create!(
      title: "reading book total 500 pages",
      goal_type: "books_total",
      goal_value: 500,
      starts_at: 2.week.ago,
      ends_at: Date.today
    )
    UserChallenge.create!(user: users(:jaina), challenge: failed_challenge, status: "failed")

    BadgeAwardJob.new.perform(users(:jaina))
    badge = Badge.find_by(badge_type: "challenge_complete")

    assert_not UserBadge.exists?(user: users(:jaina), badge: badge)
  end

  test "challenge_complete badge is linked to the correct user, not another user" do
    create_challenge_and_userchallenge(users(:jaina))

    BadgeAwardJob.new.perform(users(:jaina))
    badge = Badge.find_by(badge_type: "challenge_complete")

    assert UserBadge.exists?(user: users(:jaina), badge: badge)
    assert_not UserBadge.exists?(user: users(:leika), badge: badge)
  end

  test "does not award page_turner badge when total pages read is below 500" do
    ReadingSession.create!(user: users(:jaina), book: books(:refactoring), read_on: Date.today, pages_read: 499)
    BadgeAwardJob.new.perform(users(:jaina))
    badge = Badge.find_by(badge_type: "page_turner")

    assert_not UserBadge.exists?(user: users(:jaina), badge: badge)
  end

  test "awards page_turner badge when total pages read reaches 500 across multiple sessions" do
    ReadingSession.create!(user: users(:jaina), book: books(:refactoring), read_on: Date.today, pages_read: 510)
    ReadingSession.create!(user: users(:jaina), book: books(:pragmatic), read_on: Date.today, pages_read: 500)
    BadgeAwardJob.new.perform(users(:jaina))
    badge = Badge.find_by(badge_type: "page_turner")

    assert UserBadge.exists?(user: users(:jaina), badge: badge)
  end

  test "page_turner badge is linked to the correct user, not another user" do
    ReadingSession.create!(user: users(:jaina), book: books(:refactoring), read_on: Date.today, pages_read: 500)

    BadgeAwardJob.new.perform(users(:jaina))
    badge = Badge.find_by(badge_type: "page_turner")


    assert UserBadge.exists?(user: users(:jaina), badge: badge)
    assert_not UserBadge.exists?(user: users(:leika), badge: badge)
  end

private

  def create_finished_book_for(user)
    book = Book.create!(title: "Book #{SecureRandom.hex(4)}", author: "Test Author")
    UserBook.create!(user: user, book: book, status: "finished")
  end

  def create_challenge_and_userchallenge(user)
    challenge = Challenge.create!(
      title: "streak 7 days",
      goal_type: "streak_days",
      goal_value: 7,
      starts_at: 1.week.ago,
      ends_at: Date.today
    )
    UserChallenge.create!(
      user: user,
      challenge: challenge,
      status: "completed"
    )
  end
end
