require "fileutils"
require "monitor"
require "tempfile"

class DevelopmentReadingScenarioManifest
  class ManifestError < StandardError; end

  def initialize(path: Rails.root.join("storage/development_scenarios/week15.json"),
    lock_path: Rails.root.join("storage/development_scenarios/week15.lock"),
    as_of: Time.zone.local(2026, 10, 30, 12))
    @path = Pathname.new(path)
    @lock_path = Pathname.new(lock_path)
    @as_of = as_of
    @monitor = Monitor.new
  end

  def with_exclusive_access
    raise ManifestError, "Scenario writes are only available in development" unless Rails.env.development?
    raise ManifestError, "Another week15 operation is already running" unless @monitor.try_enter

    begin
      # A coordinator may call catalog/bootstrap services with this same manifest on the same thread.
      return yield if @lock_owner == Thread.current

      FileUtils.mkdir_p(@lock_path.dirname)
      File.open(@lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
        raise ManifestError, "Another week15 operation is already running" unless lock.flock(File::LOCK_EX | File::LOCK_NB)

        @contents = nil
        @lock_owner = Thread.current
        begin
          yield
        ensure
          @lock_owner = nil
        end
      end
    ensure
      @monitor.exit
    end
  end

  def prepare_scenario(snapshot_id:)
    require_exclusive_access
    expected = {
      "version" => 1, "scenario" => "week15", "snapshot_id" => snapshot_id,
      "seed" => 15, "as_of" => @as_of.in_time_zone.iso8601(6),
      "database" => ActiveRecord::Base.connection_db_config.database
    }
    @contents ||= @path.exist? ? JSON.parse(@path.read) : expected.deep_dup
    unless @contents.is_a?(Hash) && @contents.slice(*expected.keys) == expected
      raise ManifestError, "Snapshot, seed, reference time or database differs from the recorded week15 scenario; no records were imported."
    end
    @contents
  rescue JSON::ParserError
    raise ManifestError, "The week15 manifest contains invalid JSON; preserve it and inspect the failure before replaying."
  end

  def save_scenario
    require_exclusive_access
    raise ManifestError, "Prepare the scenario before saving its manifest" unless @contents.is_a?(Hash)

    FileUtils.mkdir_p(@path.dirname)
    Tempfile.create([ ".week15", ".json" ], @path.dirname) do |file|
      file.write(JSON.pretty_generate(@contents))
      file.write("\n")
      file.flush
      file.fsync
      File.rename(file.path, @path)
    end
  end

  private

  def require_exclusive_access
    raise ManifestError, "Open exclusive scenario access before reading or saving its manifest" unless @lock_owner == Thread.current
  end
end
