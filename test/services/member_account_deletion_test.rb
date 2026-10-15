require "test_helper"

class MemberAccountDeletionTest < ActiveSupport::TestCase
  test "account deletion removes history metrics and dependent data atomically" do
    member = users(:leika)
    ReadingMetric.find_or_create_by!(user: member)
    assert_difference("User.count", -1) { MemberAccountDeletion.new(member: member).delete_account }
    [ ReadingMetric, ReadingSession, Review, UserBook, BookClubMembership ].each do |model|
      assert_empty model.where(user_id: member.id)
    end
  end
end
