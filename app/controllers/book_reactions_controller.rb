class BookReactionsController < ReactionsController
  private

  def set_reaction_target
    @reaction_target = policy_scope(Book).find(params[:book_id])
  end

  def selection_redirect_path
    book_path(@reaction_target)
  end
end
