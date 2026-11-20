require "test_helper"
require "tmpdir"

class ProductionDemoScenarioTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  def queue_adapter_for_test
    ActiveJob::QueueAdapters::TestAdapter.new
  end

  test "a full import preserves an unresolved legacy book and continues after another book is deleted" do
    legacy = Book.create!(title: "The Great Gatsby", author: "F. Scott Fitzgerald")
    before = legacy.attributes
    Dir.mktmpdir("demo-book-conflicts-") do |directory|
      variables = ENV.to_h.merge("ALLOW_PRODUCTION_SCENARIO" => "true", "READING_SCENARIO_AS_OF" => "2026-11-17T20:00:00Z")
      ENV.stub(:[], variables.method(:[])) do
        Rails.env.stub(:production?, true) do
          scenario = DevelopmentReadingScenario.new(
            manifest_path: File.join(directory, "manifest.json"),
            password: "synthetic-scenario-test-password"
          )
          first = scenario.seed_scenario
          assert_equal 99, first.dig("static_counts", "books")
          conflict = first.dig("skipped", "skipped_book_conflicts").sole
          assert_equal "/works/OL468431W", conflict.fetch("work_key")
          assert_equal [ legacy.id ], conflict.fetch("conflicts").first.fetch("record_ids")

          deleted = Book.where.not(ol_work_key: nil).where(id: ReadingSession.select(:book_id))
            .where.not(id: BookClub.where.not(current_book_id: nil).select(:current_book_id)).first!
          deleted.destroy!
          assert_no_difference "Book.count" do
            replayed = scenario.seed_scenario
            assert_equal 98, replayed.dig("static_counts", "books")
            assert_equal 30, replayed.dig("added", "reading_sessions")
            assert_equal [ "/works/OL468431W", deleted.ol_work_key ].sort, replayed.dig("skipped", "skipped_book_conflicts").pluck("work_key").sort
          end
        end
      end
    end
    assert_equal before, legacy.reload.attributes
    assert_not_requested :any, /https?:/
  end

  test "the recorded catalog demo renders multiple single and unenrolled challenge readers and all genre filters" do
    Dir.mktmpdir("production-demo-") do |directory|
      variables = ENV.to_h.merge("ALLOW_PRODUCTION_SCENARIO" => "true", "READING_SCENARIO_AS_OF" => "2026-11-17T20:00:00Z")
      manifest = nil
      ENV.stub(:[], variables.method(:[])) do
        Rails.env.stub(:production?, true) do
          manifest = DevelopmentReadingScenario.new(
            snapshot_path: Rails.root.join("db/seeds/open_library_catalog.json"),
            manifest_path: File.join(directory, "manifest.json"),
            password: "synthetic-scenario-test-password"
          ).seed_scenario
        end
      end

      [ [ "reader01", 3 ], [ "reader11", 1 ], [ "reader21", 0 ] ].each do |identity, enrolled|
        reader = User.find_by!(email: "#{identity}@example.test")
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

      assert_equal({ "challenges" => 6, "user_challenges" => 40 }, manifest.fetch("static_counts").slice("challenges", "user_challenges"))
      assert_not_requested :any, /https?:/
    end
  end
end
