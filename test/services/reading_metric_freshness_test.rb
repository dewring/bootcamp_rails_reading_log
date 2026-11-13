require "test_helper"

class ReadingMetricFreshnessTest < ActiveSupport::TestCase
  AS_OF = Time.zone.local(2026, 11, 11, 18, 0)

  setup do
    ReadingSession.delete_all
    ReadingSession.create!(user: users(:leika), book: books(:refactoring), read_on: Date.new(2026, 11, 10), pages_read: 5)
    ReadingSession.create!(user: users(:jaina), book: books(:refactoring), read_on: Date.new(2026, 11, 10), pages_read: 5)
  end

  def freshness
    ReadingMetricFreshness.new(as_of: AS_OF).freshness
  end

  test "no saved metrics is reported as never calculated" do
    assert_equal "never_calculated", freshness.status
  end

  test "metrics for every reader saved within 20 minutes are fresh and the oldest time is reported" do
    ReadingMetric.create!(user: users(:leika), calculated_at: AS_OF - 8.minutes)
    ReadingMetric.create!(user: users(:jaina), calculated_at: AS_OF - 2.minutes)

    result = freshness

    assert_equal "fresh", result.status
    assert_equal AS_OF - 8.minutes, result.oldest_calculated_at
    assert_equal 8, result.minutes_old(AS_OF)
    assert_equal 2, result.metric_count
    assert_equal 2, result.reader_count
  end

  test "a metric older than 20 minutes makes the report stale even if others are recent" do
    ReadingMetric.create!(user: users(:leika), calculated_at: AS_OF - 21.minutes)
    ReadingMetric.create!(user: users(:jaina), calculated_at: AS_OF - 1.minute)

    assert_equal "stale", freshness.status
  end

  test "recent metrics that miss a reader with sessions are incomplete" do
    ReadingMetric.create!(user: users(:leika), calculated_at: AS_OF - 1.minute)

    result = freshness

    assert_equal "incomplete", result.status
    assert_equal 1, result.metric_count
    assert_equal 2, result.reader_count
  end
end
