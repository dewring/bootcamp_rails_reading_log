require "test_helper"

class ReadingMetricsJobTest < ActiveSupport::TestCase
  test "creates a ReadingMetric for each user with sessions" do
    ReadingSession.create!(user: users(:jaina), book: books(:refactoring), read_on: Date.current, pages_read: 10)
    ReadingSession.create!(user: users(:admin), book: books(:pragmatic), read_on: Date.current, pages_read: 10)

    ReadingMetricsJob.new.perform

    assert ReadingMetric.exists?(user: users(:jaina))
    assert ReadingMetric.exists?(user: users(:admin))
  end

  test "computes pages_today accurately" do
    ReadingSession.create!(user: users(:jaina), book: books(:refactoring), read_on: Date.current, pages_read: 30)

    ReadingMetricsJob.new.perform

    assert_equal 30, ReadingMetric.find_by(user: users(:jaina)).pages_today
  end

  test "streak is 0 when there is no session today" do
    ReadingSession.create!(user: users(:jaina), book: books(:refactoring), read_on: Date.current - 1, pages_read: 10)

    ReadingMetricsJob.new.perform

    assert_equal 0, ReadingMetric.find_by(user: users(:jaina)).current_streak
  end

  test "streak is 3 for three consecutive days including today" do
    ReadingSession.create!(user: users(:jaina), book: books(:refactoring), read_on: Date.current, pages_read: 10)
    ReadingSession.create!(user: users(:jaina), book: books(:refactoring), read_on: Date.current - 1, pages_read: 10)
    ReadingSession.create!(user: users(:jaina), book: books(:refactoring), read_on: Date.current - 2, pages_read: 10)

    ReadingMetricsJob.new.perform

    assert_equal 3, ReadingMetric.find_by(user: users(:jaina)).current_streak
  end

  test "is idempotent across multiple runs" do
    ReadingSession.create!(user: users(:jaina), book: books(:refactoring), read_on: Date.current, pages_read: 10)

    ReadingMetricsJob.new.perform

    assert_no_difference "ReadingMetric.count" do
      ReadingMetricsJob.new.perform
    end
  end
end
