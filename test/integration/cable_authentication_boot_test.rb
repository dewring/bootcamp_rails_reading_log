require "test_helper"
require "open3"

class CableAuthenticationBootTest < ActiveSupport::TestCase
  test "a first Cable connection prepares Devise mappings before reading the user session" do
    script = <<~RUBY
      require "./config/environment"

      raise "Expected unloaded mappings" unless Devise.class_variable_get(:@@mappings).empty?

      warden = Object.new
      def warden.user(scope:)
        raise "Incorrect scope" unless scope == :user
        raise "Mappings not loaded" unless Devise.class_variable_get(:@@mappings).key?(:user)
        raise "Session deserializer not configured" unless Warden::SessionSerializer.method_defined?(:user_deserialize)

        :authenticated_user
      end

      connection = ApplicationCable::Connection.allocate
      connection.instance_variable_set(:@env, { "warden" => warden })
      connection.connect
      raise "User not assigned" unless connection.current_user == :authenticated_user

      puts "CABLE_BOOT_AUTH_OK"
    RUBY

    output, errors, status = Open3.capture3(
      { "RAILS_ENV" => "test", "CI" => nil },
      RbConfig.ruby, "-e", script,
      chdir: Rails.root.to_s
    )

    assert status.success?, "Fresh-process connection failed:\n#{output}\n#{errors}"
    assert_includes output.lines.map(&:strip), "CABLE_BOOT_AUTH_OK"
  end
end
