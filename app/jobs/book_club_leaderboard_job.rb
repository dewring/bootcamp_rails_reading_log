class BookClubLeaderboardJob < ApplicationJob
  queue_as :default

  def perform(book_club_id)
    book_club = BookClub.find_by(id: book_club_id)
    return unless book_club

    # Viewer-specific controls and labels must render in the authenticated request.
    Turbo::StreamsChannel.broadcast_refresh_to(book_club)
  end
end
