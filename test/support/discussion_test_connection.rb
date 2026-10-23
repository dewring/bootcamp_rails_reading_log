require "timeout"
require "action_cable/channel/test_case"

# Collect message data at the browser boundary while using real Cable streams and workers.
class DiscussionTestConnection < ActionCable::Channel::ConnectionStub
  attr_reader :received_message_data

  def initialize(server:, user:, include_presence: false)
    super(current_user: user)
    @server = server
    @logger = ActionCable::Connection::TaggedLoggerProxy.new(server.logger, tags: [])
    @received_message_data = Queue.new
    @include_presence = include_presence
  end

  def worker_pool
    server.worker_pool
  end

  def transmit(message_data)
    data = message_data.deep_stringify_keys
    # Discussion-only tests ignore presence; presence integration tests opt in.
    return if !@include_presence && data.dig("message", "type").to_s.start_with?("presence.")

    received_message_data.push(data)
  end

  def next_message_data
    Timeout.timeout(5) { received_message_data.pop }
  end
end
