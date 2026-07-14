class WebhookDeliveryJob < ApplicationJob
  include SemanticLogger::Loggable

  queue_as :default

  discard_on ActiveRecord::RecordNotFound
  discard_on Faraday::ResourceNotFound
  retry_on Faraday::ServerError, wait: 30.seconds, attempts: 3
  retry_on Faraday::TimeoutError, wait: :polynomially_longer, attempts: 5


  def perform(webhook_endpoint, event, data)
    payload = { event: event, data: data, timestamp: Time.current.iso8601 }.to_json
    signature = OpenSSL::HMAC.hexdigest("SHA256", webhook_endpoint.secret_digest, payload)

    connection.post(webhook_endpoint.url) do |req|
      req.headers["Content-Type"] = "application/json"
      req.headers["X-Reading-Log-Signature"] = "sha256=#{signature}"
      req.body = payload
    end
  end

  private

  def connection
    Faraday.new do |f|
      f.options.timeout = 15
      f.options.open_timeout = 15
      f.response :raise_error
    end
  end
end
