require "fileutils"
require "tempfile"

class DevelopmentReadingScenarioManifest
  class ManifestError < StandardError; end

  DEFAULT_PATH = Rails.root.join("storage/development_scenarios/reading_scenario.json").freeze

  attr_reader :path

  def initialize(path: DEFAULT_PATH, as_of: DevelopmentReadingScenarioPlan.configured_reference_time)
    @path = Pathname.new(path)
    @as_of = as_of
  end

  def prepare_scenario(snapshot_id:)
    expected = {
      "version" => 1, "scenario" => "reading_scenario", "snapshot_id" => snapshot_id,
      "seed" => 15,
      "database" => ActiveRecord::Base.connection_db_config.database
    }
    expected["as_of"] = @as_of.in_time_zone.iso8601(6) if @as_of
    contents = @path.exist? ? JSON.parse(@path.read) : expected.reverse_merge("as_of" => Time.current.iso8601(6))
    unless contents.is_a?(Hash) && contents.slice(*expected.keys) == expected
      raise ManifestError, "Snapshot, seed, reference time or database differs from the recorded reading scenario; no records were imported."
    end
    Time.iso8601(contents.fetch("as_of"))
    contents
  rescue KeyError, TypeError, ArgumentError
    raise ManifestError, "The reading scenario manifest needs a valid reference time."
  rescue JSON::ParserError
    raise ManifestError, "The reading scenario manifest contains invalid JSON; preserve it and inspect the failure before replaying."
  end

  def save_scenario(contents)
    unless ReadingScenarioEnvironment.enabled?
      raise ManifestError, "Scenario writes require development or production with ALLOW_PRODUCTION_SCENARIO=true"
    end

    FileUtils.mkdir_p(@path.dirname)
    Tempfile.create([ ".reading_scenario", ".json" ], @path.dirname) do |file|
      file.write(JSON.pretty_generate(contents))
      file.write("\n")
      file.flush
      file.fsync
      File.rename(file.path, @path)
    end
  end
end
