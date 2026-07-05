require "test_helper"
class ReadingSessionsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  def queue_adapter_for_test
    ActiveJob::QueueAdapters::TestAdapter.new
  end
  test "new reading session defaults to today's date" do
    sign_in users(:leika)
    get new_book_reading_session_path(book_id: books(:refactoring))
    assert_response :success
    assert_select "input[type='date'][value='#{Date.today}']"
  end

  test "guest cannot access reading sessions" do
    get new_book_reading_session_path(book_id: books(:refactoring))
    assert_redirected_to new_user_session_path
  end
  test "create reading session shows errors on invalid submission" do
    sign_in users(:leika)
    post book_reading_sessions_path(books(:refactoring)), params: { reading_session: { read_on: "", pages_read: "" } }
    assert_response :unprocessable_entity
    assert_select "div.error-messages"
  end

  test "user create reading session" do
    sign_in users(:leika)
    post book_reading_sessions_path(books(:refactoring)), params: { reading_session: { read_on: Date.today, pages_read: 15 } }
    assert_redirected_to book_path(books(:refactoring))
  end
  test "user update reading session" do
    sign_in users(:leika)
    patch reading_session_path(reading_sessions(:one)), params: { reading_session: { pages_read: 20 } }
    assert_redirected_to dashboard_path
  end
  test "user destroy book log" do
    sign_in users(:leika)
    delete reading_session_path(reading_sessions(:one))
    assert_redirected_to dashboard_path
  end

  test "create enqueues BookProgressJob" do
    sign_in users(:leika)

    assert_enqueued_with(job: BookProgressJob) do
      post book_reading_sessions_path(books(:refactoring)), params: { reading_session: { read_on: Date.today, pages_read: 15 } }
    end
  end
end
