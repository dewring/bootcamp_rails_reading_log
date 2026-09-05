require "test_helper"

class QueueHeartbeatJobTest < ActiveSupport::TestCase
  test "pings HEARTBEAT_URL when it is configured" do
    ENV["HEARTBEAT_URL"] = "http://example.com/heartbeat"
    stub_request(:post, "http://example.com/heartbeat").to_return(status: 200)

    QueueHeartbeatJob.new.perform

    assert_requested :post, "http://example.com/heartbeat"
  ensure
    ENV.delete("HEARTBEAT_URL")
  end

  test "does not attempt a ping when HEARTBEAT_URL is not set" do
    ENV.delete("HEARTBEAT_URL")

    assert_nothing_raised do
      QueueHeartbeatJob.new.perform
    end
  end

  test "logs and does not raise when the ping fails" do
    ENV["HEARTBEAT_URL"] = "http://example.com/heartbeat"
    stub_request(:post, "http://example.com/heartbeat").to_raise(Faraday::TimeoutError)

    assert_nothing_raised do
      QueueHeartbeatJob.new.perform
    end
  ensure
    ENV.delete("HEARTBEAT_URL")
  end
end
