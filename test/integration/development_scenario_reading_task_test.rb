require "test_helper"
require "rake"
require "tmpdir"

class DevelopmentScenarioReadingTaskTest < ActiveSupport::TestCase
  test "production without opt-in reports the required flag without creating activity" do
    variables = ENV.to_h.merge("ALLOW_PRODUCTION_SCENARIO" => nil)
    ENV.stub(:[], variables.method(:[])) do
      Rails.env.stub(:production?, true) do
        assert_no_difference [ "ReadingSession.count", "ClubMessage.count" ] do
          assert_includes reading_task_error, "ALLOW_PRODUCTION_SCENARIO=true"
        end
      end
    end
  end

  test "invalid reference time reports its setting name without creating activity" do
    variables = ENV.to_h.merge("READING_SCENARIO_AS_OF" => "invalid")
    ENV.stub(:[], variables.method(:[])) do
      assert_no_difference [ "ReadingSession.count", "ClubMessage.count" ] do
        assert_includes reading_task_error, "READING_SCENARIO_AS_OF"
      end
    end
  end

  test "a missing snapshot reports the capture prerequisite without creating activity" do
    Dir.mktmpdir("reading-task-") do |directory|
      service = DevelopmentReadingScenario.new(
        snapshot_path: File.join(directory, "missing.json"),
        manifest_path: File.join(directory, "manifest.json"), lock_path: File.join(directory, "scenario.lock")
      )
      DevelopmentReadingScenario.stub(:new, service) do
        Rails.stub(:env, "development".inquiry) do
          assert_no_difference [ "ReadingSession.count", "ClubMessage.count" ] do
            assert_includes reading_task_error, "development_scenario:capture_catalog"
          end
        end
      end
      assert_not File.exist?(File.join(directory, "manifest.json"))
    end
    assert_not_requested :any, /https?:/
  end

  private

  def reading_task_error
    message = nil
    Rake.with_application do
      Rake::Task.define_task(:environment)
      load Rails.root.join("lib/tasks/development_scenario.rake")
      _output, message = capture_io do
        error = assert_raises(SystemExit) { Rake::Task["development_scenario:simulate_reading"].invoke }
        assert_equal 1, error.status
      end
    end
    message
  end
end
