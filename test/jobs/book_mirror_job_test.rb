require "test_helper"

class BookMirrorJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def queue_adapter_for_test
    ActiveJob::QueueAdapters::TestAdapter.new
  end

  test "discards job when book no longer exists" do
    book = Book.create!(title: "Temp", author: "Temp", ol_work_key: "/works/OL999W")
    book.destroy

    assert_nothing_raised do
      perform_enqueued_jobs do
        BookMirrorJob.perform_later(book)
      end
    end
  end
end
