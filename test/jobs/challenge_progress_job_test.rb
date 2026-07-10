require "test_helper"

class ChallengeProgressJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def queue_adapter_for_test
    ActiveJob::QueueAdapters::TestAdapter.new
  end

  # ── books_total ──────────────────────────────────────────────
  test "books_total: below goal before deadline stays active or in_progress" do
    challenge = Challenge.create!(
      title: "Read 5 books", goal_type: "books_total", goal_value: 5,
      starts_at: 10.days.ago, ends_at: 10.days.from_now
    )
    user_challenge = users(:leika).user_challenges.create!(challenge: challenge, status: :active, progress: 0)

    2.times do |n|
      book = Book.create!(title: "Book #{n}", author: "Someone")
      UserBook.create!(user: users(:leika), book: book, status: "finished")
    end

    ChallengeProgressJob.new.perform(users(:leika))
    user_challenge.reload

    # 2 finished out of goal_value 5 -> trace percentage_for(2, 5) and the else branch of finalize_count_based
    assert_equal "in_progress", user_challenge.status
    assert_equal 40, user_challenge.progress
  end

  test "books_total: reaching goal marks completed" do
    challenge = Challenge.create!(
      title: "Read 2 books", goal_type: "books_total", goal_value: 2,
      starts_at: 10.days.ago, ends_at: 10.days.from_now
    )
    user_challenge = users(:leika).user_challenges.create!(challenge: challenge, status: :active, progress: 0)

    2.times do |n|
      book = Book.create!(title: "Book #{n}", author: "Someone")
      UserBook.create!(user: users(:leika), book: book, status: "finished")
    end

    ChallengeProgressJob.new.perform(users(:leika))
    user_challenge.reload

    assert_equal "completed", user_challenge.status
    assert_equal 100, user_challenge.progress
  end

  test "books_total: goal not reached after deadline marks failed" do
    challenge = Challenge.create!(
      title: "Read 5 books", goal_type: "books_total", goal_value: 5,
      starts_at: 20.days.ago, ends_at: 5.days.ago
    )
    user_challenge = users(:leika).user_challenges.create!(challenge: challenge, status: :active, progress: 0)

    book = Book.create!(title: "Only Book", author: "Someone")
    UserBook.create!(user: users(:leika), book: book, status: "finished")

    ChallengeProgressJob.new.perform(users(:leika))
    user_challenge.reload

    # 1 finished out of goal_value 5, but Date.current > ends_at -> trace percentage_for(1, 5)
    assert_equal "failed", user_challenge.status
    assert_equal 20, user_challenge.progress
  end

  # ── streak_days ──────────────────────────────────────────────
  test "streak_days: consecutive days build progress" do
    challenge = Challenge.create!(
      title: "5 day streak", goal_type: "streak_days", goal_value: 5,
      starts_at: 10.days.ago, ends_at: 10.days.from_now
    )
    user_challenge = users(:jaina).user_challenges.create!(challenge: challenge, status: :active, progress: 0)

    # 3 consecutive days ending today
    [ Date.current, Date.current - 1.day, Date.current - 2.days ].each do |day|
      ReadingSession.create!(user: users(:jaina), book: books(:refactoring), read_on: day, pages_read: 10)
    end

    ChallengeProgressJob.new.perform(users(:jaina))
    user_challenge.reload

    # streak of 3 out of goal_value 5 -> trace current_streak + percentage_for(3, 5)
    assert_equal "in_progress", user_challenge.status
    assert_equal 60, user_challenge.progress
  end

  # ── pages_per_day ────────────────────────────────────────────
  test "pages_per_day: one short day fails immediately, even before deadline" do
    challenge = Challenge.create!(
      title: "20 pages a day", goal_type: "pages_per_day", goal_value: 20,
      starts_at: 3.days.ago, ends_at: 10.days.from_now
    )
    user_challenge = users(:jaina).user_challenges.create!(challenge: challenge, status: :active, progress: 0)

    ReadingSession.create!(user: users(:jaina), book: books(:refactoring), read_on: 3.days.ago, pages_read: 25)
    ReadingSession.create!(user: users(:jaina), book: books(:refactoring), read_on: 2.days.ago, pages_read: 25)
    ReadingSession.create!(user: users(:jaina), book: books(:refactoring), read_on: 1.day.ago, pages_read: 5) # short day

    ChallengeProgressJob.new.perform(users(:jaina))
    user_challenge.reload

    # one day under goal_value -> failed_day_found. What status? What progress (met_days / total_days)?
    assert_equal "failed", user_challenge.status
    assert_equal 67, user_challenge.progress
  end

  test "pages_per_day: meeting every day through the deadline marks completed" do
    challenge = Challenge.create!(
      title: "10 pages a day", goal_type: "pages_per_day", goal_value: 10,
      starts_at: 5.days.ago, ends_at: 1.day.ago
    )
    user_challenge = users(:jaina).user_challenges.create!(challenge: challenge, status: :active, progress: 0)

    (challenge.starts_at.to_date..challenge.ends_at.to_date).each do |day|
      ReadingSession.create!(user: users(:jaina), book: books(:refactoring), read_on: day, pages_read: 15)
    end

    travel_to(challenge.ends_at + 1.day) do
      ChallengeProgressJob.new.perform(users(:jaina))
    end
    user_challenge.reload

    assert_equal "completed", user_challenge.status
    assert_equal 100, user_challenge.progress
  end

  # ── cross-cutting ────────────────────────────────────────────
  test "perform does not touch completed challenges" do
    challenge = Challenge.create!(
      title: "Already done", goal_type: "books_total", goal_value: 5,
      starts_at: 10.days.ago, ends_at: 10.days.from_now
    )
    user_challenge = users(:leika).user_challenges.create!(challenge: challenge, status: :completed, progress: 100)
    # deliberately give it data that would NOT complete a fresh challenge (0 finished books)

    ChallengeProgressJob.new.perform(users(:leika))
    user_challenge.reload

    assert_equal "completed", user_challenge.status
    assert_equal 100, user_challenge.progress
  end

  test "discards job when user no longer exists" do
    user = User.create!(
      first_name: "old", last_name: "user",
      nickname: "old_user_#{SecureRandom.hex(4)}",
      email: "old_user_#{SecureRandom.hex(4)}@test.com",
      role: "user", password: "password123"
    )
    user.destroy

    assert_nothing_raised do
      perform_enqueued_jobs do
        ChallengeProgressJob.perform_later(user)
      end
    end
  end
end
