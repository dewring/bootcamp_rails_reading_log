require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "guest can sign up with all required fields" do
    post user_registration_path, params: {
      user: {
        first_name: "Jane",
        last_name: "Doe",
        nickname: "janedoe",
        email: "jane@example.com",
        password: "password123",
        password_confirmation: "password123"
      }
    }
    assert_redirected_to root_path
    assert User.find_by(email: "jane@example.com")
  end

  test "sign up fails without first name" do
    post user_registration_path, params: {
      user: {
        first_name: "",
        last_name: "Doe",
        nickname: "janedoe",
        email: "jane@example.com",
        password: "password123",
        password_confirmation: "password123"
      }
    }
    assert_response :unprocessable_entity
  end

  test "sign up fails with duplicate nickname" do
    post user_registration_path, params: {
      user: {
        first_name: "Jane",
        last_name: "Doe",
        nickname: users(:leika).nickname,
        email: "unique@example.com",
        password: "password123",
        password_confirmation: "password123"
      }
    }
    assert_response :unprocessable_entity
  end

  test "sign up fails without last name" do
    post user_registration_path, params: {
      user: {
        first_name: "Jane",
        last_name: "",
        nickname: "janedoe",
        email: "jane@example.com",
        password: "password123",
        password_confirmation: "password123"
      }
    }
    assert_response :unprocessable_entity
  end
end
