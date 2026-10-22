Warden::Manager.before_logout(scope: :user) do |user, _auth, _options|
  if user
    ActionCable.server.remote_connections.where(current_user: user).disconnect(reconnect: false)
  end
end
