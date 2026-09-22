require "test_helper"

class CableConfigurationTest < ActiveSupport::TestCase
  test "development uses Solid Cable with the cable database" do
    cable_config = YAML.load_file(Rails.root.join("config/cable.yml"), aliases: true)["development"]
    database_config = YAML.load_file(Rails.root.join("config/database.yml"), aliases: true)["development"]["cable"]

    assert_equal "solid_cable", cable_config["adapter"]
    assert_equal "cable", cable_config.dig("connects_to", "database", "writing")
    assert_equal "bootcamp_rails_reading_log_development_cable", database_config["database"]
    assert_equal "db/cable_migrate", database_config["migrations_paths"]
  end

  test "test and production keep their intended cable adapters" do
    cable_config = YAML.load_file(Rails.root.join("config/cable.yml"), aliases: true)

    assert_equal "test", cable_config["test"]["adapter"]
    assert_equal "solid_cable", cable_config["production"]["adapter"]
  end
end
