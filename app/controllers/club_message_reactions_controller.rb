class ClubMessageReactionsController < ReactionsController
  prepend_before_action :authenticate_user!

  private

  def set_reaction_target
    @book_club = policy_scope(BookClub).find(params[:book_club_id])
    authorize @book_club, :discuss?
    @reaction_target = policy_scope(@book_club.club_messages).find(params[:club_message_id])
  end

  def selection_redirect_path
    book_club_club_messages_path(@book_club, anchor: helpers.dom_id(@reaction_target))
  end
end
