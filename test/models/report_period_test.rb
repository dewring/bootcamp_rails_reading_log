require "test_helper"

class ReportPeriodTest < ActiveSupport::TestCase
  TODAY = Date.new(2026, 11, 11)

  def build_period(preset: nil, start_param: nil, end_param: nil)
    ReportPeriod.new(preset: preset, start_param: start_param, end_param: end_param, today: TODAY)
  end

  test "a blank period defaults to today only" do
    period = build_period

    assert period.valid?
    assert_equal "today", period.preset
    assert_equal TODAY..TODAY, period.dates
  end

  test "last 7 days covers today and the six preceding dates" do
    period = build_period(preset: "last_7_days")

    assert_equal Date.new(2026, 11, 5)..TODAY, period.dates
    assert_equal 7, period.date_count
  end

  test "last 28 days covers today and the 27 preceding dates" do
    period = build_period(preset: "last_28_days")

    assert_equal Date.new(2026, 10, 15)..TODAY, period.dates
    assert_equal 28, period.date_count
  end

  test "a custom three-date range keeps every requested date" do
    period = build_period(preset: "custom", start_param: "2026-11-01", end_param: "2026-11-03")

    assert period.valid?
    assert_equal [ Date.new(2026, 11, 1), Date.new(2026, 11, 2), Date.new(2026, 11, 3) ], period.dates.to_a
  end

  test "a custom range of exactly 31 dates ending today is accepted" do
    period = build_period(preset: "custom", start_param: "2026-10-12", end_param: "2026-11-11")

    assert period.valid?
    assert_equal 31, period.date_count
  end

  test "a custom range of 32 dates is rejected and falls back to today" do
    period = build_period(preset: "custom", start_param: "2026-10-11", end_param: "2026-11-11")

    refute period.valid?
    assert_equal "Choose 31 dates or fewer.", period.error_message
    assert_equal TODAY..TODAY, period.dates
  end

  test "a reversed custom range is rejected" do
    period = build_period(preset: "custom", start_param: "2026-11-05", end_param: "2026-11-01")

    refute period.valid?
    assert_equal "End date must be on or after the start date.", period.error_message
  end

  test "a custom range ending after today is rejected" do
    period = build_period(preset: "custom", start_param: "2026-11-10", end_param: "2026-11-12")

    refute period.valid?
    assert_equal "End date can't be after today (2026-11-11).", period.error_message
  end

  test "impossible, non-ISO, missing, and injected date values are rejected without raising" do
    [
      [ "2026-13-45", "2026-11-11" ],
      [ "11/01/2026", "2026-11-11" ],
      [ "", "2026-11-11" ],
      [ "2026-11-01' OR '1'='1", "2026-11-11" ],
      [ [ "2026-11-01" ], "2026-11-11" ]
    ].each do |start_param, end_param|
      period = build_period(preset: "custom", start_param: start_param, end_param: end_param)

      refute period.valid?, "expected #{start_param.inspect} to be rejected"
      assert_equal "Enter both dates in YYYY-MM-DD format.", period.error_message
      assert_equal TODAY..TODAY, period.dates
    end
  end

  test "an unknown period is rejected and falls back to today" do
    period = build_period(preset: "last_9000_days")

    refute period.valid?
    assert_equal "Choose a period from the list.", period.error_message
    assert_equal "today", period.preset
    assert_equal TODAY..TODAY, period.dates
  end
end
