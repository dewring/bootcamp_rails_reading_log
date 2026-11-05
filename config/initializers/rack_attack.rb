class Rack::Attack
  throttle("reaction writes per trusted ip", limit: 20, period: 1.minute) do |request|
    if (request.put? || request.delete?) && request.path.match?(%r{\A/(?:books/[^/]+/(?:reviews/[^/]+/)?reaction|book_clubs/[^/]+/club_messages/[^/]+/reaction)(?:\.[^/]+)?/?\z})
      direct_ip = request.get_header("REMOTE_ADDR")
      trusted_proxy = Rails.application.config.action_dispatch.trusted_proxies.any? { |proxy| proxy.include?(direct_ip) }
      trusted_proxy ? ActionDispatch::Request.new(request.env).remote_ip : direct_ip
    end
  end

  throttle("limit login attempts per ip", limit: 5, period: 20) do |request|
    if request.path == "/users/sign_in" && request.post?
      request.ip
    end
  end
end
