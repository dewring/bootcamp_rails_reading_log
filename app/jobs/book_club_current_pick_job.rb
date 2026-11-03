class BookClubCurrentPickJob < ApplicationJob
  queue_as :default

  def perform(book_club_id)
    book_club = BookClub.find_by(id: book_club_id)
    return unless book_club

    # Viewer-specific controls and labels must render in the authenticated request.
    Turbo::StreamsChannel.broadcast_refresh_to(book_club)
    book_club.preload_covers
    Turbo::StreamsChannel.broadcast_replace_to(
      book_club, :discussion_current_pick,
      target: ActionView::RecordIdentifier.dom_id(book_club, :current_pick),
      partial: "book_clubs/current_pick",
      locals: { book_club: book_club, variant: :discussion }
    )
  end
end
