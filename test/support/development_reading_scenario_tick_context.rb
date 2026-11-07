require "tmpdir"
require_relative "development_reading_scenario_setup"

module DevelopmentReadingScenarioTickContext
  extend ActiveSupport::Concern

  included do
    include ActiveJob::TestHelper
    include ActionCable::TestHelper
    include DevelopmentReadingScenarioSetup
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
    @initial_books = Book.pluck(:id)
    @initial_clubs = BookClub.pluck(:id)
    @initial_genres = Genre.all.map(&:attributes)
    @initial_badges = Badge.all.map(&:attributes)
    @directory = Pathname.new(Dir.mktmpdir("booknook-tick-"))
    @paths = { snapshot_path: @directory.join("catalog.json"), manifest_path: @directory.join("manifest.json"), lock_path: @directory.join("scenario.lock") }
    docs = Array.new(100) do |index|
      { "key" => "/works/OL#{215_000 + index}W", "title" => "Tick source #{index}", "author_name" => [ "Source Author" ], "number_of_pages_median" => 1000 }
    end
    stub_request(:get, "https://openlibrary.org/search.json").with(query: hash_including(page: "1"))
      .to_return(status: 200, body: { docs: docs }.to_json)
    in_development do
      OpenLibraryCatalogCapture.new(snapshot_path: @paths.fetch(:snapshot_path), lock_path: @directory.join("capture.lock"), contact_email: "contact@example.test").capture_catalog
      @baseline = prepare_scenario_data do |manifest|
        @seed = DevelopmentReadingScenarioManifest.stub(:new, manifest) do
          DevelopmentReadingScenario.new(**@paths, password: "synthetic-scenario-test-password")
        end
        @seed.seed_baseline
      end
    end
    WebMock.reset!
    @tick = DevelopmentReadingScenarioTick.new(**@paths)
  end

  def clean_tick_context
    BookClub.where.not(id: @initial_clubs).find_each(&:destroy!)
    actors = User.where.not(id: @initial_users).pluck(:id)
    ReadingSession.where(user_id: actors).find_each(&:destroy!)
    User.where(id: actors).find_each(&:destroy!)
    Book.where.not(id: @initial_books).find_each(&:destroy!)
    restore_tick_shared_records(Genre, @initial_genres)
    restore_tick_shared_records(Badge, @initial_badges)
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

  def restore_tick_shared_records(model, originals)
    model.where.not(id: originals.map { |attributes| attributes.fetch("id") }).find_each(&:destroy!)
    originals.each do |attributes|
      row = model.find_by(id: attributes.fetch("id"))
      row ? row.update!(attributes.except("id")) : model.create!(attributes)
    end
  end
end
