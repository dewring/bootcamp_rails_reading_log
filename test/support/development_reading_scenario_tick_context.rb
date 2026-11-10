require "tmpdir"

module DevelopmentReadingScenarioTickContext
  extend ActiveSupport::Concern

  included do
    include ActiveJob::TestHelper
    include ActionCable::TestHelper
    self.use_transactional_tests = false
    setup :prepare_tick_context
    teardown :clean_tick_context

    def queue_adapter_for_test
      ActiveJob::QueueAdapters::TestAdapter.new
    end
  end

  private

  def prepare_tick_context
    @initial_users = User.pluck(:id)
    @directory = Pathname.new(Dir.mktmpdir("booknook-tick-"))
    @paths = { snapshot_path: @directory.join("catalog.json"), manifest_path: @directory.join("manifest.json"), lock_path: @directory.join("scenario.lock") }
    docs = Array.new(100) do |index|
      { "key" => "/works/OL#{215_000 + index}W", "title" => "Tick source #{index}", "author_name" => [ "Source Author" ], "number_of_pages_median" => 1000 }
    end
    stub_request(:get, "https://openlibrary.org/search.json").with(query: hash_including(page: "1"))
      .to_return(status: 200, body: { docs: docs }.to_json)
    in_development do
      OpenLibraryCatalogCapture.new(snapshot_path: @paths.fetch(:snapshot_path), lock_path: @directory.join("capture.lock"), contact_email: "contact@example.test").capture_catalog
      @seed = DevelopmentReadingScenario.new(**@paths, password: "synthetic-scenario-test-password")
      @baseline = @seed.seed_baseline
    end
    WebMock.reset!
    @tick = DevelopmentReadingScenarioTick.new(**@paths)
  end

  def clean_tick_context
    FileUtils.remove_entry(@directory)
  end

  def in_development(&block)
    Rails.stub(:env, "development".inquiry, &block)
  end

  def advance
    in_development { @tick.advance_scenario(tick: "tick1") }
  end

  def tick_records(manifest, group)
    manifest.fetch("ticks").fetch("tick1").fetch(group)
  end

  def tick_ids(manifest)
    [ "reading_sessions", "club_messages" ].to_h do |group|
      [ group, tick_records(manifest, group).transform_values { |record| record.fetch("id") } ]
    end
  end

  def club(identity)
    BookClub.find(@baseline.dig("community", "records", "book_clubs", identity, "id"))
  end

  def queue_count(name)
    enqueued_jobs.count { |job| job.fetch("job_class") == name }
  end
end
