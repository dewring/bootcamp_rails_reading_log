class ReviewReactionsController < ReactionsController
  private

  def set_reaction_target
    @book = policy_scope(Book).find(params[:book_id])
    @reaction_target = policy_scope(@book.reviews).find(params[:review_id])
  end

  def selection_redirect_path
    book_path(@book, anchor: helpers.dom_id(@reaction_target))
  end
end
