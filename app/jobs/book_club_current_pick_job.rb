class BookClubCurrentPickJob < ApplicationJob
  queue_as :default

  def perform(book_club_id)
    book_club = BookClub.includes(:current_book).find_by(id: book_club_id)
    return unless book_club

    Turbo::StreamsChannel.broadcast_replace_to(
      book_club,
      target: ActionView::RecordIdentifier.dom_id(book_club, :current_pick),
      partial: "book_clubs/current_pick",
      locals: { book_club: book_club }
    )
  end
end
