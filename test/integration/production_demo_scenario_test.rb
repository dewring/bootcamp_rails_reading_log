require "test_helper"
require "tmpdir"

class ProductionDemoScenarioTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  def queue_adapter_for_test
    ActiveJob::QueueAdapters::TestAdapter.new
  end

  test "the recorded catalog demo renders multiple single and unenrolled challenge readers and all genre filters" do
    Dir.mktmpdir("production-demo-") do |directory|
      variables = ENV.to_h.merge("ALLOW_PRODUCTION_SCENARIO" => "true", "READING_SCENARIO_AS_OF" => "2026-11-17T20:00:00Z")
      manifest = nil
      ENV.stub(:[], variables.method(:[])) do
        Rails.env.stub(:production?, true) do
          manifest = DevelopmentReadingScenario.new(
            snapshot_path: Rails.root.join("db/seeds/open_library_catalog.json"),
            manifest_path: File.join(directory, "manifest.json"), lock_path: File.join(directory, "scenario.lock"),
            password: "synthetic-scenario-test-password"
          ).seed_scenario
        end
      end

      [ [ "reader01", 3 ], [ "reader11", 1 ], [ "reader21", 0 ] ].each do |identity, enrolled|
        reader_id = manifest.dig("bootstrap", "records", "users", identity, "id")
        reader = User.find(reader_id)
        sign_in reader

        get challenges_path

        assert_response :success
        assert_select ".challenge-summary-tile--ongoing strong", text: enrolled.to_s
        assert_select ".challenge-summary-tile--available strong", text: (6 - enrolled).to_s
        assert_select ".challenge-section--ongoing .challenge-card", count: enrolled
        assert_select ".challenge-section--available .challenge-enroll-form", count: 6 - enrolled
        sign_out reader
      end

      Genre::GENRES.each do |name|
        get books_path, params: { genre: name }, as: :json

        assert_response :success
        found = response.parsed_body.fetch("books")
        assert_not_empty found, "The recorded catalog should supply demo books for #{name}"
        assert found.all? { |book| book.fetch("genres").any? { |genre| genre.fetch("name") == name } }
      end

      assert_equal({ "challenges" => 6, "user_challenges" => 40 }, manifest.dig("challenges", "actual_counts"))
      assert_not_requested :any, /https?:/
    end
  end
end
