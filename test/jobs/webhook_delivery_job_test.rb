require "test_helper"

class WebhookDeliveryJobTest < ActiveSupport::TestCase
  setup do
    @webhook_endpoint = users(:leika).webhook_endpoints.create!(
      url: "http://example.com/webhook",
      secret_digest: "shared-secret",
      active: true,
      events: [ "challenge_completed" ]
    )
  end

  test "signs the payload with the endpoint's secret" do
    travel_to Time.zone.parse("2026-07-14 12:00:00 UTC") do
      expected_payload = { event: "challenge_completed", data: { challenge_id: 1 }, timestamp: Time.current.iso8601 }.to_json
      expected_signature = OpenSSL::HMAC.hexdigest("sha256", "shared-secret", expected_payload)

      stub_request(:post, "http://example.com/webhook")
        .with(body: expected_payload, headers: { "X-Reading-Log-Signature" => "sha256=#{expected_signature}" })
        .to_return(status: 200)

      WebhookDeliveryJob.new.perform(@webhook_endpoint, "challenge_completed", { challenge_id: 1 })

      assert_requested :post, "http://example.com/webhook",
        body: expected_payload,
        headers: { "X-Reading-Log-Signature" => "sha256=#{expected_signature}" }
    end
  end

  test "raises Faraday::TimeoutError on a timeout" do
    stub_request(:post, "http://example.com/webhook").to_raise(Faraday::TimeoutError)

    assert_raises(Faraday::TimeoutError) do
      WebhookDeliveryJob.new.perform(@webhook_endpoint, "challenge_completed", { challenge_id: 1 })
    end
  end

  test "raises Faraday::ResourceNotFound on a 404" do
    stub_request(:post, "http://example.com/webhook").to_return(status: 404)

    assert_raises(Faraday::ResourceNotFound) do
      WebhookDeliveryJob.new.perform(@webhook_endpoint, "challenge_completed", { challenge_id: 1 })
    end
  end
end
