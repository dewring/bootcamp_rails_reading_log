require "test_helper"

class BookClubTest < ActiveSupport::TestCase
  test "valid book club is valid" do
    assert BookClub.new(name: "Sci-Fi Society").valid?
  end

  test "name must be present" do
    assert_not BookClub.new(name: "").valid?
  end
end
