require "timeout"
require "action_cable/channel/test_case"

# Collect message data at the browser boundary while using real Cable streams and workers.
class DiscussionTestConnection < ActionCable::Channel::ConnectionStub
  attr_reader :received_message_data

  def initialize(server:, user:)
    super(current_user: user)
    @server = server
    @logger = ActionCable::Connection::TaggedLoggerProxy.new(server.logger, tags: [])
    @received_message_data = Queue.new
  end

  def worker_pool
    server.worker_pool
  end

  def transmit(message_data)
    received_message_data.push(message_data.deep_stringify_keys)
  end

  def next_message_data
    Timeout.timeout(5) { received_message_data.pop }
  end
end
