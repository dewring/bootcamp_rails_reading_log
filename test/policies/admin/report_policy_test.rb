require "test_helper"

class Admin::ReportPolicyTest < ActiveSupport::TestCase
  test "guests and regular readers cannot view the reading report but admins can" do
    [ nil, users(:leika) ].each do |reader|
      refute Admin::ReportPolicy.new(reader, :report).show?
    end

    assert Admin::ReportPolicy.new(users(:admin), :report).show?
  end
end
