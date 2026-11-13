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
end
