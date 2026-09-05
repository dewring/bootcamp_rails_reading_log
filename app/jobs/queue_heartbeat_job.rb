class QueueHeartbeatJob < ApplicationJob
  include SemanticLogger::Loggable

  queue_as :default

  def perform
    return unless ENV["HEARTBEAT_URL"]

    begin
      Faraday.post(ENV["HEARTBEAT_URL"])
    rescue => e
      logger.error("Heartbeat ping failed", error_message: e.message)
    end
  end
end
