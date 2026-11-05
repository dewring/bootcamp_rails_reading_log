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
end
