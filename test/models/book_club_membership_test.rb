require "test_helper"

class BookClubMembershipTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActionCable::TestHelper

  def queue_adapter_for_test
    ActiveJob::QueueAdapters::TestAdapter.new
  end

  def setup
    @book_club = BookClub.create!(name: "Sci-Fi Society")
  end

  test "valid membership is valid" do
    membership = BookClubMembership.new(book_club: @book_club, user: users(:leika), role: "member")
    assert membership.valid?
  end

  test "role must be owner or member" do
    membership = BookClubMembership.new(book_club: @book_club, user: users(:leika), role: "president")
    assert_not membership.valid?
  end

  test "user cannot join the same club twice" do
    BookClubMembership.create!(book_club: @book_club, user: users(:leika), role: "member")
    duplicate = BookClubMembership.new(book_club: @book_club, user: users(:leika), role: "member")

    assert_not duplicate.valid?
  end

  test "enqueues a leaderboard refresh after membership changes" do
    clear_enqueued_jobs

    assert_enqueued_with(job: BookClubLeaderboardJob, args: [ @book_club.id ]) do
      @book_club.book_club_memberships.create!(user: users(:leika), role: "member")
    end
  end

  test "membership deletion broadcasts a discussion access check" do
    membership = @book_club.book_club_memberships.create!(user: users(:jaina), role: "member")
    stream = ClubDiscussionChannel.broadcasting_for(@book_club)

    assert_broadcast_on stream, { type: "access.recheck" } do
      membership.destroy!
    end
  end

  test "membership deletion does not broadcast before commit or after rollback" do
    membership = @book_club.book_club_memberships.create!(user: users(:jaina), role: "member")
    stream = ClubDiscussionChannel.broadcasting_for(@book_club)

    assert_no_broadcasts stream do
      BookClubMembership.transaction(requires_new: true) do
        membership.destroy!
        assert_no_broadcasts stream
        raise ActiveRecord::Rollback
      end
    end

    assert BookClubMembership.exists?(membership.id)
  end
end
