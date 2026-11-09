require "test_helper"
require "rake"

class DevelopmentScenarioReactionsTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("development_scenario:seed_reactions")
    @task = Rake::Task["development_scenario:seed_reactions"]
    @task.reenable
  end

  test "the development task delegates reaction seeding and prints owned counts" do
    seeder = Minitest::Mock.new
    seeder.expect(:seed_reactions, { "reactions" => { "actual_counts" => DevelopmentReadingScenarioReactions::COUNTS } })

    output, = capture_io do
      DevelopmentReadingScenarioReactions.stub(:new, seeder) { @task.invoke }
    end

    seeder.verify
    assert_includes output, '"book_reactions":160'
    assert_includes output, '"likes":120'
    assert_includes output, '"dislikes":40'
  end

  test "the task reports the development-only guard without creating reactions" do
    assert_no_difference "Reaction.count" do
      _output, error_output = capture_io do
        error = assert_raises(SystemExit) { @task.invoke }
        assert_equal 1, error.status
      end
      assert_includes error_output, "only available in development"
    end
  end

  test "the named refresh command delegates once and explains its fixed reference time" do
    Rake.with_application do
      Rake::Task.define_task(:environment)
      load Rails.root.join("lib/tasks/development_scenario.rake")
      service = Minitest::Mock.new
      result = {
        "as_of" => "2026-10-30T12:00:00Z",
        "reactions" => { DevelopmentReadingScenarioReactions::REFRESH_ACTION => {
          "status" => "complete", "reaction_id" => 123, "updated_at" => "2026-10-29T12:00:00Z"
        } }
      }
      service.expect(:refresh_old_hit_reaction, result)

      output, = capture_io do
        DevelopmentReadingScenarioReactions.stub(:new, service) do
          Rake::Task["development_scenario:refresh_old_hit_reaction"].invoke
        end
      end

      service.verify
      assert_includes output, "reaction ID: 123"
      assert_includes output, "2026-10-30T12:00:00Z"
      assert_includes output, "increases from 2 to 3"
      assert_includes output, "Repeating this command preserves the timestamp"
      assert_includes output, "homepage uses its current request time"
    end
  end

  test "the refresh command reports the development-only guard without changing reactions" do
    Rake.with_application do
      Rake::Task.define_task(:environment)
      load Rails.root.join("lib/tasks/development_scenario.rake")
      assert_no_difference "Reaction.count" do
        _output, error_output = capture_io do
          error = assert_raises(SystemExit) { Rake::Task["development_scenario:refresh_old_hit_reaction"].invoke }
          assert_equal 1, error.status
        end
        assert_includes error_output, "only available in development"
      end
    end
  end
end
