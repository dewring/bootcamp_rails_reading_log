module Admin::BookClubsHelper
  def admin_club_owner(club)
    club.book_club_memberships.find { |membership| membership.role == "owner" }&.user&.nickname || "Owner not assigned"
  end
end
