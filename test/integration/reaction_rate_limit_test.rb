require "test_helper"

class ReactionRateLimitTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    Rack::Attack.reset!
    @reader = users(:leika)
    @club = BookClub.create!(name: "Rate limit discussion")
    @club.book_club_memberships.create!(user: @reader, role: "member")
    @message = @club.club_messages.create!(user: @reader, body: "Rate limit post")
    @paths = [
      book_reaction_path(books(:refactoring)),
      book_review_reaction_path(books(:refactoring), reviews(:review1)),
      book_club_club_message_reaction_path(@club, @message)
    ]
    sign_in @reader
  end

  teardown do
    Rack::Attack.reset!
  end

  test "the twenty first write across all three resources is throttled and the next window resets" do
    travel_to Time.current.beginning_of_minute do
      20.times do |index|
        path = @paths[index % 3]
        if index.even?
          put path, params: { kind: "like" }, as: :turbo_stream
        else
          delete path, as: :turbo_stream
        end
        assert_response :success
      end

      put @paths.first, params: { kind: "wow" }, as: :turbo_stream
      assert_response :too_many_requests
      get @paths.first
      assert_response :success
      travel 1.minute
      put @paths.first, params: { kind: "wow" }, as: :turbo_stream
      assert_response :success
    end
  end

  test "changing a forged forwarded IP does not bypass a limit for an untrusted direct client" do
    20.times do |index|
      put @paths.first, params: { kind: "like" }, as: :turbo_stream,
        headers: { "REMOTE_ADDR" => "203.0.113.7", "X-Forwarded-For" => "198.51.100.#{index + 1}" }
      assert_response :success
    end

    put @paths.last, params: { kind: "love" }, as: :turbo_stream,
      headers: { "REMOTE_ADDR" => "203.0.113.7", "X-Forwarded-For" => "198.51.100.200" }
    assert_response :too_many_requests
  end

  test "distinct trusted client IPs have independent limits behind a trusted proxy" do
    headers = { "REMOTE_ADDR" => "127.0.0.1", "X-Forwarded-For" => "203.0.113.11" }
    20.times do
      delete @paths.first, headers: headers, as: :turbo_stream
      assert_response :success
    end
    delete @paths.first, headers: headers, as: :turbo_stream
    assert_response :too_many_requests
    delete @paths.first, headers: headers.merge("X-Forwarded-For" => "203.0.113.12"), as: :turbo_stream
    assert_response :success
  end

  test "native method override writes share the same rate limit" do
    20.times do
      post @paths.first, params: { _method: "put", kind: "like" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :success
    end
    post @paths.last, params: { _method: "delete" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :too_many_requests
  end

  test "equivalent route formats trailing slashes and accepted ID suffixes cannot bypass the shared limit" do
    variants = [ @paths.first, "#{@paths.first}.turbo_stream", "#{@paths.first}/", "/books/#{books(:refactoring).id}-title/reaction" ]
    20.times do |index|
      put variants[index % variants.length], params: { kind: "like" }, as: :turbo_stream
      assert_response :success
    end

    variants.each do |path|
      delete path, as: :turbo_stream
      assert_response :too_many_requests
    end
  end
end
