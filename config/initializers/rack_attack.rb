class Rack::Attack
  throttle("limit login attempts per ip", limit: 5, period: 20) do |request|
    if request.path == "/users/sign_in" && request.post?
      request.ip
    end
  end
end
