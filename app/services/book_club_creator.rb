class BookClubCreator
  def initialize(book_club:, owner:)
    @book_club = book_club
    @owner = owner
  end

  def create_club
    BookClub.transaction do
      @book_club.save!
      @book_club.book_club_memberships.create!(user: @owner, role: "owner")
    end
    @book_club
  end
end
