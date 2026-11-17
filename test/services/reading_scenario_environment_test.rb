require "test_helper"

class ReadingScenarioEnvironmentTest < ActiveSupport::TestCase
  test "development permits scenarios without a production opt-in" do
    assert scenario_enabled?("development", nil)
  end

  test "production requires an explicit true opt-in" do
    assert scenario_enabled?("production", "true")

    [ nil, "false", "1", "TRUE" ].each do |value|
      assert_not scenario_enabled?("production", value)
    end
  end

  test "the production opt-in does not permit test or staging environments" do
    [ "test", "staging" ].each do |environment|
      assert_not scenario_enabled?(environment, "true")
    end
  end

  private

  def scenario_enabled?(environment, opt_in)
    variables = ENV.to_h.merge("ALLOW_PRODUCTION_SCENARIO" => opt_in)
    ENV.stub(:[], variables.method(:[])) do
      Rails.stub(:env, environment.inquiry) { ReadingScenarioEnvironment.enabled? }
    end
  end
end
