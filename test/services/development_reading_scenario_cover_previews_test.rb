require "test_helper"
require_relative "../support/development_reading_scenario_cover_preview_context"

class DevelopmentReadingScenarioCoverPreviewsTest < ActiveSupport::TestCase
  include DevelopmentReadingScenarioCoverPreviewContext

  test "explicit setup queues at most twelve source-backed previews without HTTP and retains one missing cover" do
    result = prepare_previews
    report = result.fetch("cover_previews")
    assert_equal 12, cover_jobs.length
    assert_equal 12, report.fetch("limit")
    assert_equal({ "selected" => 12, "statuses" => { "queued" => 12 }, "source_unavailable" => 80 }, report.fetch("actual_counts"))
    assert_equal "source_cover_id_missing", report.fetch("missing_case").fetch("reason")
    assert_not Book.find(report.fetch("missing_case").fetch("book_id")).cover_image.attached?
    records(result).each_value do |record|
      job = cover_jobs.find { |candidate| candidate.fetch("job_id") == record.fetch("job_id") }
      assert_equal "low", job.fetch("queue_name")
      assert_equal [ Book.find(record.fetch("book_id")), record.fetch("cover_id") ], ActiveJob::Arguments.deserialize(job.fetch("arguments"))
    end
    assert_not_requested :any, /https?:/
  end

  test "repeated preparation keeps the same selection and never queues the remaining source covers" do
    first = prepare_previews
    jobs = cover_jobs.dup
    second = prepare_previews

    assert_equal jobs, cover_jobs
    assert_equal records(first).transform_values { |record| record.fetch("job_id") }, records(second).transform_values { |record| record.fetch("job_id") }
    assert_equal first.fetch("cover_previews").fetch("missing_case"), second.fetch("cover_previews").fetch("missing_case")
    assert_equal 12, records(second).length
    assert_not_requested :any, /https?:/
  end

  test "an existing preview is reused without replacing its image or queueing another download" do
    book = Book.find_by!(ol_work_key: @docs.first.fetch("key"))
    book.cover_image.attach(io: File.open(file_fixture("cover_test.jpg")), filename: "existing.jpg", content_type: "image/jpeg")
    blob_id = book.cover_image.blob.id
    clear_enqueued_jobs
    result = prepare_previews

    assert_equal 11, cover_jobs.length
    assert_equal "attached", records(result).fetch(book.ol_work_key).fetch("status")
    assert_equal blob_id, book.reload.cover_image.blob.id
    assert_not_requested :any, /https?:/
  end

  test "no source cover IDs produces an honest empty preview selection without fabricated IDs" do
    @docs.each { |doc| doc["cover_i"] = nil }
    write_preview_catalog(alternate: true)
    report = prepare_previews.fetch("cover_previews")

    assert_empty cover_jobs
    assert_empty report.fetch("records")
    assert_equal 100, report.fetch("actual_counts").fetch("source_unavailable")
    assert_not_requested :any, /https?:/
  end

  test "when every source has a cover ID one preview is explicitly omitted without changing source metadata" do
    @docs.each_with_index { |doc, index| doc["cover_i"] = 325_000 + index }
    write_preview_catalog(alternate: true)
    source = @paths.fetch(:snapshot_path).read
    report = prepare_previews.fetch("cover_previews")

    assert_equal "preview_intentionally_omitted", report.fetch("missing_case").fetch("reason")
    assert_not report.fetch("records").key?(report.fetch("missing_case").fetch("work_key"))
    assert_equal source, @paths.fetch(:snapshot_path).read
    assert_equal 12, cover_jobs.length
  end

  test "normal cover jobs attach valid images while a discarded download is not automatically queued again" do
    first = prepare_previews
    unavailable = records(first).values.first
    stub_cover_downloads
    stub_request(:get, "https://covers.openlibrary.org/b/id/#{unavailable.fetch('cover_id')}-M.jpg").to_return(status: 404)
    perform_enqueued_jobs(only: CoverAttachJob)
    report = in_development { @previews.reconcile_previews }.fetch("cover_previews")

    assert_equal({ "attached" => 11, "queued" => 1 }, report.fetch("actual_counts").fetch("statuses"))
    assert_not report.fetch("records").values.first.key?("job_status")
    assert_not Book.find(unavailable.fetch("book_id")).cover_image.attached?
    assert_not Book.find(report.fetch("missing_case").fetch("book_id")).cover_image.attached?
    prepare_previews
    assert_empty cover_jobs
  end

  test "repeated preparation does not duplicate a retry scheduled by the existing cover job" do
    first = prepare_previews
    retrying = records(first).values.first
    stub_cover_downloads
    stub_request(:get, "https://covers.openlibrary.org/b/id/#{retrying.fetch('cover_id')}-M.jpg").to_raise(SocketError)
    perform_enqueued_jobs(only: CoverAttachJob)
    report = in_development { @previews.reconcile_previews }.fetch("cover_previews")

    assert_equal "queued", report.fetch("records").values.first.fetch("status")
    assert_equal 1, cover_jobs.length
    assert_equal retrying.fetch("job_id"), cover_jobs.first.fetch("job_id")
    prepare_previews
    assert_equal 1, cover_jobs.length
  end
end
