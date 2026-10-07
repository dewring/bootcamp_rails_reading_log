require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "guest sees the Figma-inspired sign-up page with separate name fields" do
    get new_user_registration_path

    assert_response :success
    assert_select "body.auth-page"
    assert_select ".auth-page-shell--sign-up"
    assert_select "h1", text: "Create your account"
    assert_select "input[name='user[first_name]'][placeholder='Jane']", count: 1
    assert_select "input[name='user[last_name]'][placeholder='Doe']", count: 1
    assert_select "input[name='user[nickname]'][placeholder='booklover42']", count: 1
    assert_select "input[name='user[email]'][placeholder='you@example.com']", count: 1
  end

  test "signed-in user sees the Figma-inspired settings page" do
    sign_in users(:leika)

    get edit_user_registration_path

    assert_response :success
    assert_select "html[data-theme='light']"
    assert_select "main[aria-label='Settings']"
    assert_select "a.my-log-navigation-item--active[href='#{edit_user_registration_path}']", text: "Settings"
    assert_select "input[name='user[first_name]'][value='leika']"
    assert_select "input[name='user[last_name]'][value='kim']"
    assert_select "input[name='user[nickname]'][value='martita']"
    assert_select "input[name='user[email]'][disabled]", value: users(:leika).email
    assert_select ".settings-email-row + small", text: "Email address cannot be changed."
    assert_select ".settings-field small", text: /At least 8 characters/
    assert_select ".settings-input img", count: 0
    assert_select "input.settings-save-button[value='Save Changes']", count: 1
    assert_select ".profile-avatar--sidebar .profile-avatar-initials", text: users(:leika).nickname.first(2).upcase
    assert_select ".profile-avatar--settings .profile-avatar-initials", text: users(:leika).nickname.first(2).upcase
    assert_select "input[type='file'][name='user[avatar]']", count: 1
    assert_select "label.settings-upload-button", text: /Upload Photo/
  end

  test "signed-in user can update first and last name from settings" do
    sign_in users(:leika)

    patch user_registration_path, params: {
      user: {
        first_name: "Updated",
        last_name: "Reader",
        nickname: "updatedreader",
        email: users(:leika).email,
        current_password: "password123"
      }
    }

    assert_response :redirect
    assert_redirected_to edit_user_registration_path
    assert_equal "Updated", users(:leika).reload.first_name
    assert_equal "Reader", users(:leika).last_name
    assert_equal "updatedreader", users(:leika).nickname
  end

  test "signed-in user can update nickname without current password" do
    sign_in users(:leika)

    patch user_registration_path, params: {
      user: {
        first_name: users(:leika).first_name,
        last_name: users(:leika).last_name,
        nickname: "profileonly"
      }
    }

    assert_response :redirect
    assert_redirected_to edit_user_registration_path
    assert_equal "profileonly", users(:leika).reload.nickname
  end

  test "signed-in user cannot change email from settings" do
    sign_in users(:leika)

    patch user_registration_path, params: {
      user: {
        first_name: users(:leika).first_name,
        last_name: users(:leika).last_name,
        nickname: "updatedreader",
        email: "changed@example.com",
        current_password: "password123"
      }
    }

    assert_response :redirect
    assert_redirected_to edit_user_registration_path
    assert_equal users(:leika).email, users(:leika).reload.email
    assert_equal "updatedreader", users(:leika).nickname
  end

  test "signed-in user can upload and remove a profile photo from settings" do
    sign_in users(:leika)

    patch user_registration_path, params: {
      user: { avatar: fixture_file_upload("cover_test.jpg", "image/jpeg") }
    }

    assert_redirected_to edit_user_registration_path
    assert users(:leika).reload.avatar.attached?
    assert_match(/\Aimage\//, users(:leika).avatar.content_type)

    patch user_registration_path, params: { user: { remove_avatar: "1" } }

    assert_redirected_to edit_user_registration_path
    assert_not users(:leika).reload.avatar.attached?
  end

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
