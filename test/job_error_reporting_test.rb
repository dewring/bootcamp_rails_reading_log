require "test_helper"

class FakeLogger
  attr_reader :calls

  def initialize
    @calls = []
  end

  def warn(message, payload = {})
    @calls << [ :warn, message, payload ]
  end

  def error(message, payload = {})
    @calls << [ :error, message, payload ]
  end
end

class BoomJob < ApplicationJob
  def perform
    raise "boom"
  end
end

class JobErrorReportingTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def queue_adapter_for_test
    ActiveJob::QueueAdapters::TestAdapter.new
  end

  test "logs when a job is discarded" do
    book = Book.create!(title: "Temp", author: "Temp")
    book.destroy
    fake_logger = FakeLogger.new

    allow(SemanticLogger).to receive(:[]).and_call_original
    allow(SemanticLogger).to receive(:[]).with("JobErrorReporting").and_return(fake_logger)
    perform_enqueued_jobs do
      CoverAttachJob.perform_later(book, 123)
    end

    assert_equal 1, fake_logger.calls.size
    level, message, payload = fake_logger.calls.first
    assert_equal :warn, level
    assert_equal "Job discarded", message
    assert_equal "CoverAttachJob", payload[:job_class]
  end

  test "logs when a job fails with an unhandled error" do
    fake_logger = FakeLogger.new

    allow(SemanticLogger).to receive(:[]).and_call_original
    allow(SemanticLogger).to receive(:[]).with("JobErrorReporting").and_return(fake_logger)
    assert_raises(RuntimeError) do
      BoomJob.perform_now
    end

    assert_equal 1, fake_logger.calls.size
    level, message, payload = fake_logger.calls.first
    assert_equal :error, level
    assert_equal "BoomJob", payload[:job_class]
  end
end
