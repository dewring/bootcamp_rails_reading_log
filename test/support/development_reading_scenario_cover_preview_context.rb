require "tmpdir"

module DevelopmentReadingScenarioCoverPreviewContext
  extend ActiveSupport::Concern

  included do
    include ActiveJob::TestHelper
    self.use_transactional_tests = false
    setup :prepare_preview_context
    teardown :clean_preview_context

    def queue_adapter_for_test
      ActiveJob::QueueAdapters::TestAdapter.new
    end
  end

  private

  def prepare_preview_context
    @initial_users = User.pluck(:id)
    @initial_books = Book.pluck(:id)
    @initial_clubs = BookClub.pluck(:id)
    @initial_genres = Genre.all.map(&:attributes)
    @initial_badges = Badge.all.map(&:attributes)
    @directory = Pathname.new(Dir.mktmpdir("booknook-previews-"))
    @docs = Array.new(100) do |index|
      { "key" => "/works/OL#{225_000 + index}W", "title" => "Cover source #{index}", "author_name" => [ "Source Author" ],
        "number_of_pages_median" => 1000, "cover_i" => index < 20 ? 325_000 + index : nil }
    end
    write_preview_catalog
  end

  def write_preview_catalog(alternate: false)
    prefix = alternate ? "alternate" : "original"
    @paths = { snapshot_path: @directory.join("#{prefix}-catalog.json"), manifest_path: @directory.join("#{prefix}-manifest.json"), lock_path: @directory.join("#{prefix}.lock") }
    stub_request(:get, "https://openlibrary.org/search.json").with(query: hash_including(page: "1"))
      .to_return(status: 200, body: { docs: @docs }.to_json)
    in_development do
      OpenLibraryCatalogCapture.new(snapshot_path: @paths.fetch(:snapshot_path), lock_path: @directory.join("capture.lock"), contact_email: "contact@example.test").capture_catalog
    end
    @catalog = OpenLibraryCatalogReplay.new(**@paths)
    WebMock.reset!
    clear_enqueued_jobs
  end

  def clean_preview_context
    BookClub.where.not(id: @initial_clubs).find_each(&:destroy!)
    actors = User.where.not(id: @initial_users).pluck(:id)
    # Cleanup should not enqueue progress, badge, and challenge jobs for discarded records.
    ReadingSession.where(user_id: actors).delete_all
    UserBook.where(user_id: actors).delete_all
    User.where(id: actors).find_each(&:destroy!)
    Book.where.not(id: @initial_books).find_each(&:destroy!)
    [ [ Genre, @initial_genres ], [ Badge, @initial_badges ] ].each do |model, originals|
      model.where.not(id: originals.map { |attributes| attributes.fetch("id") }).find_each(&:destroy!)
      originals.each do |attributes|
        row = model.find_by(id: attributes.fetch("id"))
        row ? row.update!(attributes.except("id")) : model.create!(attributes)
      end
    end
    FileUtils.remove_entry(@directory)
  end

  def in_development(&block)
    Rails.stub(:env, "development".inquiry, &block)
  end

  def prepare_previews
    in_development { @catalog.replay_catalog }
  end

  def cover_jobs
    enqueued_jobs.select { |job| job.fetch("job_class") == "CoverAttachJob" }
  end

  def records(manifest)
    manifest.fetch("cover_previews").fetch("records")
  end

  def stub_cover_downloads
    stub_request(:get, %r{https://covers.openlibrary.org/b/id/\d+-M\.jpg})
      .to_return(status: 200, body: file_fixture("cover_test.jpg").read, headers: { "Content-Type" => "image/jpeg" })
  end
end
