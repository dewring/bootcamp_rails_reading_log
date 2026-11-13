# How current the saved ReadingMetric rows are at the report's as_of time.
#
# ReadingMetric is a per-reader summary that ReadingMetricsJob recalculates on
# a recurring schedule (every 10 minutes by default, config/recurring.yml) for
# every reader with reading sessions. calculated_at is when the job last saved
# a row, not when a reader last read. The oldest calculated_at is reported
# because it shows whether every reader is up to date, not just one.
class ReadingMetricFreshness
  # Two missed runs of the default 10-minute schedule.
  STALE_AFTER = 20.minutes

  Result = Data.define(:status, :oldest_calculated_at, :metric_count, :reader_count) do
    def minutes_old(as_of)
      ((as_of - oldest_calculated_at) / 60).floor
    end
  end

  def initialize(as_of:)
    @as_of = as_of
  end

  def freshness
    oldest_calculated_at = ReadingMetric.minimum(:calculated_at)
    metric_count = ReadingMetric.where.not(calculated_at: nil).count
    reader_count = ReadingSession.distinct.count(:user_id)

    Result.new(
      status: status_for(oldest_calculated_at, metric_count, reader_count),
      oldest_calculated_at: oldest_calculated_at,
      metric_count: metric_count,
      reader_count: reader_count
    )
  end

  private

  def status_for(oldest_calculated_at, metric_count, reader_count)
    return "never_calculated" if oldest_calculated_at.nil?
    return "stale" if oldest_calculated_at < @as_of - STALE_AFTER
    return "incomplete" if metric_count < reader_count

    "fresh"
  end
end
