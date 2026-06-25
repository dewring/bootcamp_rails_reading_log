require "test_helper"

class GenrePolicyTest < ActiveSupport::TestCase
  test "anyone can view genres" do
    assert GenrePolicy.new(nil, genres(:fiction)).show?
  end

  test "admin can manage genres" do
    policy = GenrePolicy.new(users(:admin), genres(:fiction))

    assert policy.create?
    assert policy.update?
    assert policy.destroy?
  end

  test "regular user cannot manage genres" do
    refute GenrePolicy.new(users(:leika), genres(:fiction)).create?
  end
end
