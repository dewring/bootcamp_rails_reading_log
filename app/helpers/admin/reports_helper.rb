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

  # Share of all pages read in the period; zero-safe for an empty period.
  def report_page_share(pages_read, total_pages_read)
    return "N/A" if total_pages_read.zero?

    number_to_percentage(pages_read * 100.0 / total_pages_read, precision: 1)
  end

  # aria-sort tells screen readers which column the leaderboard is ranked by.
  def report_aria_sort(leaderboard, sort_key)
    return "descending" if leaderboard.sort == sort_key

    "none"
  end
end
