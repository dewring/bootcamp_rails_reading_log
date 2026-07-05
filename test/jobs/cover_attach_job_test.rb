require "test_helper"
require "open-uri"

class CoverAttachJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def queue_adapter_for_test
    ActiveJob::QueueAdapters::TestAdapter.new
  end

  def setup
    CoverAttachJob
    @book = Book.create!(title: "Harry Potter", author: "J. K. Rowling")
  end

  test "is idempotent when cover already attached" do
    @book.cover_image.attach(io: StringIO.new("fake image data"), filename: "existing.jpg", content_type: "image/jpeg")

    assert_no_difference "ActiveStorage::Blob.count" do
      CoverAttachJob.perform_now(@book, 999)
    end
  end

  test "discards job when record no longer exists" do
    book = Book.create!(title: "Temp", author: "Temp")
    book.destroy

    assert_nothing_raised do
      perform_enqueued_jobs do
        CoverAttachJob.perform_later(book, 123)
      end
    end
  end

  test "raises CoverNotFoundError on a 404" do
    stub_request(:get, "https://covers.openlibrary.org/b/id/404-M.jpg")
      .to_return(status: 404, body: "")

    assert_raises(CoverNotFoundError) do
      CoverAttachJob.new.perform(@book, 404)
    end
  end
  test "re-raises OpenURI::HTTPError on a 503" do
    stub_request(:get, "https://covers.openlibrary.org/b/id/503-M.jpg")
      .to_return(status: 503, body: "")

    assert_raises(OpenURI::HTTPError) do
      CoverAttachJob.new.perform(@book, 503)
    end
  end
end
