require "test_helper"

class ReadingSessionRecorderTest < ActiveSupport::TestCase
  test "successfully records a reading session" do
    book = books(:refactoring)
    user = users(:leika)
    attributes = { read_on: Date.today, pages_read: 10 }

    reading_session = ReadingSessionRecorder.new(book, user, attributes).record

    assert reading_session.persisted?
  end

  test "does not record a reading session with invalid attributes" do
    book = books(:refactoring)
    user = users(:leika)
    attributes = { read_on: Date.today, pages_read: -1 }

    reading_session = ReadingSessionRecorder.new(book, user, attributes).record

    refute reading_session.persisted?
  end
end
