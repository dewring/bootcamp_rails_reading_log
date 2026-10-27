require "test_helper"
require "action_cable/connection/test_case"

class ApplicationCable::ConnectionTest < ActionCable::Connection::TestCase
  tests ApplicationCable::Connection

  test "a signed in user connects even when Warden retains a stale default scope" do
    user = users(:leika)
    warden = session_proxy(user)

    assert_nil warden.user

    connect env: { "warden" => warden }

    assert_equal user, connection.current_user
  end

  test "a guest connection is rejected" do
    assert_reject_connection do
      connect env: { "warden" => session_proxy }
    end
  end

  test "a session with an outdated authentication salt is rejected" do
    user = users(:leika)
    warden = session_proxy(user, salt: "outdated-salt")

    assert_reject_connection do
      connect env: { "warden" => warden }
    end
  end

  private

  def session_proxy(user = nil, salt: nil)
    Devise.mappings
    manager = Warden::Manager.new(nil)
    manager.config.default_scope = :default
    env = Rack::MockRequest.env_for("/cable")
    env["rack.session"] = {}
    if user
      serialized = User.serialize_into_session(user)
      serialized[1] = salt if salt
      env["rack.session"]["warden.user.user.key"] = serialized
    end
    Warden::Proxy.new(env, manager)
  end
end
