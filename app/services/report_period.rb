# The date range an admin report covers. Dates come from request params, so
# every value is validated here before any report query uses it. An invalid
# request falls back to the default period and keeps the error to show.
class ReportPeriod
  PRESET_DATE_COUNTS = {
    "today" => 1,
    "last_7_days" => 7,
    "last_28_days" => 28
  }.freeze
  PERIOD_OPTIONS = [
    [ "Today", "today" ],
    [ "Last 7 days", "last_7_days" ],
    [ "Last 28 days", "last_28_days" ],
    [ "Custom range", "custom" ]
  ].freeze
  CUSTOM_PRESET = "custom"
  DEFAULT_PRESET = "today"
  MAX_DATE_COUNT = 31
  ISO_DATE_FORMAT = /\A\d{4}-\d{2}-\d{2}\z/

  attr_reader :preset, :start_param, :end_param, :error_message, :start_on, :end_on

  def initialize(preset:, start_param:, end_param:, today:)
    @today = today
    @requested_preset = preset.to_s.presence || DEFAULT_PRESET
    @preset = known_preset?(@requested_preset) ? @requested_preset : DEFAULT_PRESET
    @start_param = start_param.to_s
    @end_param = end_param.to_s
    @custom_start_on = parse_iso_date(@start_param)
    @custom_end_on = parse_iso_date(@end_param)
    @error_message = validation_error
    assign_dates
  end

  def valid?
    error_message.nil?
  end

  def custom?
    preset == CUSTOM_PRESET
  end

  def dates
    start_on..end_on
  end

  def date_count
    dates.count
  end

  private

  def validation_error
    return "Choose a period from the list." unless known_preset?(@requested_preset)
    return nil unless custom?
    return nil if awaiting_custom_dates?
    return "Enter both dates in YYYY-MM-DD format." if @custom_start_on.nil? || @custom_end_on.nil?
    return "End date must be on or after the start date." if @custom_end_on < @custom_start_on
    return "End date can't be after today (#{@today.iso8601})." if @custom_end_on > @today
    return "Choose #{MAX_DATE_COUNT} dates or fewer." if custom_date_count > MAX_DATE_COUNT

    nil
  end

  def known_preset?(value)
    PRESET_DATE_COUNTS.key?(value) || value == CUSTOM_PRESET
  end

  def assign_dates
    if valid? && custom? && !awaiting_custom_dates?
      @start_on = @custom_start_on
      @end_on = @custom_end_on
    else
      assign_preset_dates
    end
  end

  # Custom input that is invalid or not entered yet shows the default
  # period's data, never partial input.
  def assign_preset_dates
    date_count = PRESET_DATE_COUNTS.fetch(@preset) { PRESET_DATE_COUNTS.fetch(DEFAULT_PRESET) }
    @end_on = @today
    @start_on = @today - (date_count - 1)
  end

  # Choosing "Custom range" submits the form before any date is picked.
  # That is a normal step, not an error.
  def awaiting_custom_dates?
    custom? && @start_param.blank? && @end_param.blank?
  end

  def custom_date_count
    (@custom_end_on - @custom_start_on).to_i + 1
  end

  def parse_iso_date(value)
    return nil unless value.match?(ISO_DATE_FORMAT)

    Date.strptime(value, "%Y-%m-%d")
  rescue Date::Error
    nil
  end
end
