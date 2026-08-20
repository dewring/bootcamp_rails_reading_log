require "test_helper"

class BookClubsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "guest cannot create a book club" do
    post book_clubs_path, params: { book_club: { name: "Sci-Fi Society" } }
    assert_redirected_to new_user_session_path
  end

  test "creating a club makes the creator its owner" do
    sign_in users(:leika)

    post book_clubs_path, params: { book_club: { name: "Sci-Fi Society", description: "Space and robots." } }
    book_club = BookClub.find_by!(name: "Sci-Fi Society")

    assert_redirected_to book_club_path(book_club)
    assert book_club.book_club_memberships.exists?(user: users(:leika), role: "owner")
  end

  test "a user can join a club they are not a member of" do
    book_club = BookClub.create!(name: "Sci-Fi Society")
    book_club.book_club_memberships.create!(user: users(:leika), role: "owner")

    sign_in users(:jaina)
    post join_book_club_path(book_club)

    assert_redirected_to book_club_path(book_club)
    assert book_club.book_club_memberships.exists?(user: users(:jaina), role: "member")
  end

  test "joining a club a user is already a member of is rejected" do
    book_club = BookClub.create!(name: "Sci-Fi Society")
    book_club.book_club_memberships.create!(user: users(:leika), role: "owner")

    sign_in users(:leika)
    post join_book_club_path(book_club)

    assert_response :redirect
    assert_equal 1, book_club.book_club_memberships.where(user: users(:leika)).count
  end

  test "a member can leave a club" do
    book_club = BookClub.create!(name: "Sci-Fi Society")
    book_club.book_club_memberships.create!(user: users(:leika), role: "owner")
    book_club.book_club_memberships.create!(user: users(:jaina), role: "member")

    sign_in users(:jaina)
    delete leave_book_club_path(book_club)

    assert_redirected_to book_clubs_path
    assert_not book_club.book_club_memberships.exists?(user: users(:jaina))
  end

  test "a non-member cannot leave a club" do
    book_club = BookClub.create!(name: "Sci-Fi Society")
    book_club.book_club_memberships.create!(user: users(:leika), role: "owner")

    sign_in users(:jaina)
    delete leave_book_club_path(book_club)

    assert_response :redirect
  end
end
