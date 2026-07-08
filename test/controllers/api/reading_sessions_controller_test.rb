require "test_helper"
class Api::ReadingSessionsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  def queue_adapter_for_test
    ActiveJob::QueueAdapters::TestAdapter.new
  end

  test "index returns user's reading sessions" do
    sign_in users(:leika)
    get api_reading_sessions_path, as: :json

    assert_response :success
  end
  test "show returns a reading session" do
    sign_in users(:leika)
    get api_reading_session_path(reading_sessions(:one)), as: :json
    assert_response :success
  end
  test "create returns 201 with valid params" do
    sign_in users(:leika)
    post api_reading_sessions_path,
         params: { book_id: books(:refactoring).id,
                   reading_session: { read_on: Date.today, pages_read: 10 } },
         as: :json

    assert_response :created
  end
  test "create enqueues BookProgressJob" do
    sign_in users(:leika)
    assert_enqueued_with(job: BookProgressJob) do
      post api_reading_sessions_path,
           params: { book_id: books(:refactoring).id,
                     reading_session: { read_on: Date.today, pages_read: 10 } },
           as: :json
    end
    assert_response :created
  end
  test "returns 401 when not logged in" do
    get api_reading_sessions_path, as: :json

    assert_response :unauthorized
  end
  test "returns 403 when accessing another user's session" do
    sign_in users(:jaina)
    get api_reading_session_path(reading_sessions(:one)), as: :json

    assert_response :forbidden
  end
  test "returns 404 when session does not exist" do
    sign_in users(:leika)
    get api_reading_session_path(999999), as: :json

    assert_response :not_found
  end
  test "returns 422 with invalid params" do
    sign_in users(:leika)
    post api_reading_sessions_path,
         params: { book_id: books(:refactoring).id,
                   reading_session: { read_on: Date.today, pages_read: -1 } },
         as: :json

    assert_response :unprocessable_entity
  end
end
