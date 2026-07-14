class InboundWebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token

  def receive
    payload = request.raw_post
    provided_signature = request.headers["X-Reading-Log-Signature"].to_s.delete_prefix("sha256=")

    verified = WebhookEndpoint.where(active: true).any? do |endpoint|
      expected_signature = OpenSSL::HMAC.hexdigest("sha256", endpoint.secret_digest, payload)
      ActiveSupport::SecurityUtils.secure_compare(expected_signature, provided_signature)
    end

    if verified
      head :ok
    else
      head :unauthorized
    end
  end
end
