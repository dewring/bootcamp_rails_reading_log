require "test_helper"

class InboundWebhooksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @secret = "test-secret-#{SecureRandom.hex(8)}"
    @webhook_endpoint = users(:leika).webhook_endpoints.create!(
      url: "http://localhost:3000/inbound_webhooks",
      secret_digest: @secret,
      active: true,
      events: [ "challenge_completed" ]
    )
    @payload = { event: "challenge_completed", data: { challenge_id: 1 } }.to_json
  end

  test "correct signature returns 200" do
    signature = OpenSSL::HMAC.hexdigest("sha256", @secret, @payload)

    post inbound_webhooks_path,
      params: @payload,
      headers: { "Content-Type" => "application/json", "X-Reading-Log-Signature" => "sha256=#{signature}" }

    assert_response :ok
  end

  test "wrong signature returns 401" do
    post inbound_webhooks_path,
      params: @payload,
      headers: { "Content-Type" => "application/json", "X-Reading-Log-Signature" => "sha256=not-the-real-signature" }

    assert_response :unauthorized
  end

  test "missing signature header returns 401" do
    post inbound_webhooks_path, params: @payload, headers: { "Content-Type" => "application/json" }

    assert_response :unauthorized
  end
end
