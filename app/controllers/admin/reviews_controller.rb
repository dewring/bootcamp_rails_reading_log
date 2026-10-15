class Admin::ReviewsController < ApplicationController
  include RequireAuthenticatedAdmin
  layout "admin"

  def index
    authorize [ :admin, Review ]
    @query = params[:q].to_s.strip
    @rating = params[:rating].to_s if ("0".."5").include?(params[:rating].to_s)
    reviews = policy_scope([ :admin, Review ]).matching_text(@query)
    reviews = reviews.where(rating: @rating) if @rating
    reviews = reviews.preload(:user, :book).order(created_at: :desc, id: :desc)
    @pagy, @reviews = pagy(:offset, reviews, limit: 4)
    @selected_review = reviews.find_by(id: params[:review_id]) if params[:review_id].present?
    @selected_review ||= @reviews.first
  end

  def destroy
    review = policy_scope([ :admin, Review ]).find(params[:id])
    authorize [ :admin, review ]
    review.destroy!
    redirect_to admin_reviews_path(q: params[:q].presence, rating: params[:rating].presence), notice: "Review deleted."
  end
end
