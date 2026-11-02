require "test_helper"
require_relative "../support/development_reading_scenario_tick_context"
require_relative "../support/discussion_test_connection"

class DevelopmentReadingScenarioPrivacyTest < ActionDispatch::IntegrationTest
  include DevelopmentReadingScenarioTickContext
  include Devise::Test::IntegrationHelpers

  test "a tick journal entry is readable by its owner and cannot be read edited or deleted by another reader" do
    manifest = advance
    session = ReadingSession.find(tick_ids(manifest).fetch("reading_sessions").fetch("reading1"))
    owner = session.user
    sign_in owner
    get api_reading_session_path(session), as: :json
    assert_response :success
    assert_equal session.notes, response.parsed_body.fetch("notes")
    sign_out owner
    sign_in reader("reader07")

    get api_reading_session_path(session), as: :json
    assert_response :forbidden
    assert_equal({ "error" => "Forbidden" }, response.parsed_body)
    get edit_reading_session_path(session), as: :json
    assert_response :forbidden
    patch reading_session_path(session), params: { reading_session: { notes: "Attempted edit by another reader" } }, as: :json
    assert_response :forbidden
    assert_equal session.notes, session.reload.notes
    assert_no_difference "ReadingSession.count" do
      delete reading_session_path(session), as: :json
      assert_response :forbidden
    end

    get book_reading_journal_path(session.book)
    assert_response :success
    assert_not_includes response.body, session.notes
    assert_select ".reading-detail-timeline-item", count: 2
    get reading_sessions_path, as: :json
    assert_response :success
    assert_equal [ reader("reader07").id ], response.parsed_body.map { |record| record.fetch("user_id") }.uniq
    assert_not_includes response.parsed_body.map { |record| record.fetch("id") }, session.id
  end

  test "shared scenario discussion JSON HTML and leaderboard HTML exclude private notes and email" do
    advance
    sign_in reader("reader07")
    target = club("steady")
    get book_club_club_messages_path(target), as: :json
    assert_response :success
    assert_equal 28, response.parsed_body.fetch("total_posts")
    assert_shared_content_is_private_safe(response.body)
    response.parsed_body.fetch("messages").each do |message|
      assert_equal [ "avatar_url", "id", "nickname" ], message.fetch("author").keys.sort
    end

    get book_club_club_messages_path(target)
    assert_response :success
    assert_includes response.body, "Synthetic discussion."
    assert_shared_content_is_private_safe(response.body)
    get book_club_leaderboard_path(target)
    assert_response :success
    assert_includes response.body, reader("reader08").nickname
    assert_shared_content_is_private_safe(response.body)
  end

  test "a synthetic nonmember can see the club overview but is denied discussion leaderboard and Cable access" do
    outsider = reader("reader01")
    sign_in outsider
    target = club("steady")
    get book_club_path(target)
    assert_response :success
    assert_select ".book-club-sidebar-navigation a", text: "Discussion", count: 0
    get book_club_club_messages_path(target), as: :json
    assert_response :forbidden
    assert_equal({ "error" => "Forbidden" }, response.parsed_body)
    get book_club_leaderboard_path(target), as: :json
    assert_response :forbidden

    with_privacy_cable_server do |server, connections|
      connection = connect_to_club(server, outsider, target, connections)
      assert_equal "reject_subscription", connection.next_message_data.fetch("type")
      advance
      server.worker_pool.executor.shutdown
      assert server.worker_pool.executor.wait_for_termination(5)
      assert connection.received_message_data.empty?
    end
  end

  test "two authorized scenario viewers receive the committed tick discussion event without private notes or email" do
    target = club("steady")
    with_privacy_cable_server do |server, connections|
      [ reader("reader07"), reader("reader08") ].each do |viewer|
        connection = connect_to_club(server, viewer, target, connections)
        assert_equal "confirm_subscription", connection.next_message_data.fetch("type")
      end
      manifest = advance
      post_id = tick_ids(manifest).fetch("club_messages").fetch("discussion1")
      expected = ClubMessage.find(post_id).discussion_payload.deep_stringify_keys

      connections.each do |connection|
        event = connection.next_message_data.fetch("message")
        assert_equal "message.created", event.fetch("type")
        assert_equal expected, event.fetch("message")
        assert_equal 28, event.fetch("total_posts")
        assert_shared_content_is_private_safe(event.to_json)
      end
    end
    assert_not_requested :any, /https?:/
  end

  private

  def reader(identity)
    User.find(@baseline.fetch("bootstrap").fetch("records").fetch("users").fetch(identity).fetch("id"))
  end

  def assert_shared_content_is_private_safe(content)
    assert_not_includes content, "Synthetic journal."
    assert_not_includes content, '"notes":'
    assert_not_includes content, "@example.test"
  end

  def connect_to_club(server, user, target, connections)
    connection = DiscussionTestConnection.new(server: server, user: user)
    connections.push(connection)
    identifier = { channel: "ClubDiscussionChannel", book_club_id: target.id }.to_json
    connection.subscriptions.add("identifier" => identifier)
    connection
  end

  def with_privacy_cable_server
    presence = instance_double(ClubPresence, renew_connection: [], active_member_ids: [], remove_connection: [])
    allow(ClubPresence).to receive(:new).and_return(presence)
    config = ActionCable::Server::Configuration.new
    config.logger = Rails.logger
    config.cable = { "adapter" => "inline" }
    config.worker_pool_size = 1
    server = ActionCable::Server::Base.new(config: config)
    connections = []
    ActionCable.stub(:server, -> { server }) { yield server, connections }
  ensure
    connections&.each { |connection| connection.subscriptions.unsubscribe_from_all }
    if server
      server.worker_pool.executor.shutdown
      assert server.worker_pool.executor.wait_for_termination(5)
      server.restart
      server.event_loop.stop
    end
  end
end
