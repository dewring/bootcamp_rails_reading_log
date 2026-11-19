module Admin::ReportsHelper
  # Date#to_fs(:long) zero-pads the day ("November 05"), so the report uses
  # the same unpadded style as the member list's dates.
  def report_date(date)
    date.strftime("%B %-d, %Y")
  end

  def report_range_title(period)
    return report_date(period.start_on) if period.date_count == 1

    "#{report_date(period.start_on)} – #{report_date(period.end_on)}"
  end

  # The period params to carry along when another report control is submitted.
  def report_period_params(period)
    return { period: period.preset } unless period.custom?

    { period: period.preset, start: period.start_param, end: period.end_param }
  end

  # aria-sort tells screen readers which column the leaderboard is ranked by.
  def report_aria_sort(leaderboard, sort_key)
    return report_sort_aria_direction(leaderboard.direction) if leaderboard.sort == sort_key

    "none"
  end

  # Zero-safe percentage: an empty denominator shows "N/A", not an error.
  def report_percentage(part, whole)
    return "N/A" if whole.zero?

    number_to_percentage(part * 100.0 / whole, precision: 1)
  end

  REPORT_FRESHNESS_LABELS = {
    "fresh" => "Fresh",
    "incomplete" => "Some readers missing",
    "stale" => "Stale",
    "never_calculated" => "Never calculated"
  }.freeze

  def report_freshness_label(status)
    REPORT_FRESHNESS_LABELS.fetch(status)
  end

  REPORT_DIRECTION_LABELS = { "desc" => "Highest first", "asc" => "Lowest first" }.freeze

  # Trigger text naming the metric and direction, e.g. "Pages read · Highest first".
  def report_sort_label(leaderboard)
    metric = leaderboard.sort_options.find { |_, value| value == leaderboard.sort }.first
    "#{metric} · #{REPORT_DIRECTION_LABELS.fetch(leaderboard.direction)}"
  end

  # One menu group per metric, each offering highest and lowest first.
  def report_sort_groups(leaderboard, &path_for)
    leaderboard.sort_options.map do |label, sort|
      options = REPORT_DIRECTION_LABELS.map do |direction, direction_label|
        selected = leaderboard.sort == sort && leaderboard.direction == direction
        { label: direction_label, path: path_for.call(sort, direction), selected: selected }
      end
      { label: label, options: options }
    end
  end

  private

  def report_sort_aria_direction(direction)
    direction == "asc" ? "ascending" : "descending"
  end
end
