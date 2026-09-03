require "test_helper"

class RequireAuthenticatedAdminTest < ActiveSupport::TestCase
  test "wires up authenticate_user! and RequireAdmin" do
    dummy_class = Class.new(ActionController::Base) do
      include RequireAuthenticatedAdmin
    end

    callback_names = dummy_class._process_action_callbacks.map(&:filter)

    assert_includes callback_names, :authenticate_user!
    assert dummy_class.ancestors.include?(RequireAdmin)
  end
end
