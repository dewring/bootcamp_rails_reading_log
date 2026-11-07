require "test_helper"

class BookClubLeaderboardSnapshotTest < ActiveSupport::TestCase
  setup do
    @club = BookClub.create!(name: "Snapshot circle")
  end

  test "the database permits only one snapshot per club" do
    BookClubLeaderboardSnapshot.create!(book_club: @club)

    assert_raises ActiveRecord::RecordNotUnique do
      BookClubLeaderboardSnapshot.transaction(requires_new: true) do
        BookClubLeaderboardSnapshot.create!(book_club: @club)
      end
    end
  end

  test "the database rejects a missing club and a null leader set" do
    assert_raises ActiveRecord::InvalidForeignKey do
      BookClubLeaderboardSnapshot.transaction(requires_new: true) do
        BookClubLeaderboardSnapshot.new(book_club_id: 0).save!(validate: false)
      end
    end

    assert_raises ActiveRecord::NotNullViolation do
      BookClubLeaderboardSnapshot.transaction(requires_new: true) do
        BookClubLeaderboardSnapshot.create!(book_club: @club, leader_user_ids: nil)
      end
    end
  end

  test "database deletion of a club also removes its snapshot" do
    snapshot = BookClubLeaderboardSnapshot.create!(book_club: @club)

    BookClub.where(id: @club.id).delete_all

    assert_not BookClubLeaderboardSnapshot.exists?(snapshot.id)
  end

  test "deleting a historical book clears its reference without discarding the leader snapshot" do
    book = Book.create!(title: "Historical pick", author: "An Author")
    snapshot = BookClubLeaderboardSnapshot.create!(book_club: @club, current_book: book, leader_user_ids: [ users(:leika).id ])

    book.destroy!

    assert_nil snapshot.reload.current_book_id
    assert_equal [ users(:leika).id ], snapshot.leader_user_ids
  end
end
