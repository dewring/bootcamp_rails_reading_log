module ReactionsHelper
  def reaction_selection_path(target)
    case target
    when Book
      book_reaction_path(target)
    when Review
      book_review_reaction_path(target.book_id, target)
    when ClubMessage
      book_club_club_message_reaction_path(target.book_club_id, target)
    end
  end
end
