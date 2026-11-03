require "test_helper"
require_relative "../support/development_reading_scenario_cover_preview_context"

class DevelopmentReadingScenarioCoverPreviewsRecoveryTest < ActiveSupport::TestCase
  include DevelopmentReadingScenarioCoverPreviewContext

  test "interruption after enqueue does not submit the same cover request again" do
    original = File.method(:rename)
    File.stub(:rename, ->(source, destination) {
      raise IOError, "Interrupted after queue acknowledgement" if Pathname.new(destination) == @paths.fetch(:manifest_path) && cover_jobs.any?

      original.call(source, destination)
    }) do
      assert_raises(IOError) { prepare_previews }
    end
    first_id = cover_jobs.sole.fetch("job_id")
    result = prepare_previews

    assert_equal 12, cover_jobs.length
    assert_equal 1, cover_jobs.count { |job| job.fetch("job_id") == first_id }
    assert_nil records(result).values.first.fetch("job_id")
    assert_equal "requested", records(result).values.first.fetch("status")
  end

  test "an uncertain enqueue is reported without automatically creating a replacement job" do
    original = File.method(:rename)
    File.stub(:rename, ->(source, destination) {
      result = original.call(source, destination)
      if Pathname.new(destination) == @paths.fetch(:manifest_path) && JSON.parse(@paths.fetch(:manifest_path).read).dig("cover_previews", "records")&.values&.first&.fetch("status") == "requested"
        raise IOError, "Interrupted before queue acknowledgement"
      end
      result
    }) do
      assert_raises(IOError) { prepare_previews }
    end
    assert_empty cover_jobs
    report = prepare_previews.fetch("cover_previews")

    assert_equal 11, cover_jobs.length
    assert_equal "requested", report.fetch("records").values.first.fetch("status")
    assert_not report.fetch("records").values.first.key?("job_status")
  end

  test "altered source cover IDs in the manifest are refused before any new enqueue" do
    result = prepare_previews
    records(result).values.first["cover_id"] += 1
    @paths.fetch(:manifest_path).write(JSON.generate(result))
    jobs = cover_jobs.dup

    error = assert_raises(DevelopmentReadingScenarioCoverPreviews::PreviewError) { prepare_previews }
    assert_includes error.message, "differs from the captured catalog"
    assert_equal jobs, cover_jobs
  end

  test "an image manually added to the missing-cover case is preserved and reported instead of removed" do
    result = prepare_previews
    book = Book.find(result.fetch("cover_previews").fetch("missing_case").fetch("book_id"))
    book.cover_image.attach(io: File.open(file_fixture("cover_test.jpg")), filename: "manual.jpg", content_type: "image/jpeg")
    blob_id = book.cover_image.blob.id

    assert_raises(DevelopmentReadingScenarioCoverPreviews::PreviewError) { prepare_previews }
    assert_equal blob_id, book.reload.cover_image.blob.id
  end

  test "non-development and overlapping preparation are refused without enqueueing jobs or HTTP" do
    assert_not @paths.fetch(:manifest_path).exist?
    assert_raises(OpenLibraryCatalogReplay::ReplayError) { @catalog.replay_catalog }
    Rails.stub(:env, "production".inquiry) do
      assert_raises(OpenLibraryCatalogReplay::ReplayError) { @catalog.replay_catalog }
    end
    File.open(@paths.fetch(:lock_path), File::RDWR | File::CREAT, 0o600) do |lock|
      lock.flock(File::LOCK_EX | File::LOCK_NB)
      assert_raises(OpenLibraryCatalogReplay::ReplayError) { prepare_previews }
    end

    assert_empty cover_jobs
    assert_not @paths.fetch(:manifest_path).exist?
    assert_not_requested :any, /https?:/
  end

  test "offline baseline replay and ticks preserve downloaded previews without further cover calls" do
    first = prepare_previews
    stub_cover_downloads
    perform_enqueued_jobs(only: CoverAttachJob)
    WebMock.reset!
    in_development do
      scenario = DevelopmentReadingScenario.new(**@paths, password: "synthetic-scenario-test-password")
      scenario.seed_baseline
      DevelopmentReadingScenarioTick.new(**@paths).advance_scenario(tick: "tick1")
      replayed = scenario.seed_baseline
      assert_equal first.fetch("cover_previews").fetch("missing_case"), replayed.fetch("cover_previews").fetch("missing_case")
      assert_equal records(first).transform_values { |record| record.fetch("job_id") }, records(replayed).transform_values { |record| record.fetch("job_id") }
      assert_equal 303, replayed.dig("baseline", "actual_counts", "reading_sessions")
      assert_equal 82, replayed.dig("baseline", "actual_counts", "club_messages")
    end
    assert_equal 12, Book.where.not(id: @initial_books).joins(:cover_image_attachment).count
    assert_empty cover_jobs
    assert_not_requested :any, /https?:/
  end
end
