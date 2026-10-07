class Admin::ChallengesController < ApplicationController
  include RequireAuthenticatedAdmin
  layout "admin", only: [ :index, :create ]

  before_action :set_challenge, only: [ :update, :destroy ]

  def index
    authorize Challenge

    @challenges = policy_scope(Challenge).order(starts_at: :desc, created_at: :desc)
    @selected_challenge = selected_challenge
    @is_new_challenge = params[:new_challenge].present?
    @detail_challenge = @is_new_challenge ? Challenge.new(active: true) : @selected_challenge
  end

  def create
    @challenge = Challenge.new(challenge_params)
    authorize @challenge
    if @challenge.save
      redirect_to admin_root_path(challenge_id: @challenge.id), notice: "Challenge added!"
    else
      @challenges = policy_scope(Challenge).order(starts_at: :desc, created_at: :desc)
      @selected_challenge = nil
      @is_new_challenge = true
      @detail_challenge = @challenge
      render :index, status: :unprocessable_entity
    end
  end
  def update
    authorize @challenge
    if @challenge.update(challenge_params)
      redirect_to admin_root_path(challenge_id: @challenge.id), notice: "Challenge updated."
    else
      redirect_to admin_root_path(challenge_id: @challenge.id), alert: @challenge.errors.full_messages.to_sentence
    end
  end
  def destroy
    authorize @challenge
    @challenge.destroy
    redirect_to admin_root_path, notice: "Challenge deleted."
  end

  private

  def selected_challenge
    @challenges.find_by(id: params[:challenge_id]) if params[:challenge_id].present?
  end

  def set_challenge
    @challenge = Challenge.find(params[:id])
  end

  def challenge_params
    params.require(:challenge).permit(:title, :goal_type, :goal_value, :starts_at, :ends_at, :active)
  end
end
