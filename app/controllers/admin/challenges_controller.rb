class Admin::ChallengesController < ApplicationController
  before_action :authenticate_user!
  include RequireAdmin
  before_action :set_challenge, only: [ :edit, :update, :destroy ]

  def new
    @challenge = Challenge.new
    authorize @challenge
  end
  def create
    @challenge = Challenge.new(challenge_params)
    authorize @challenge
    if @challenge.save
      redirect_to challenge_path(@challenge), notice: "Challenge added!"
    else
      render :new, status: :unprocessable_entity
    end
  end
  def edit
    authorize @challenge
  end
  def update
    authorize @challenge
    if @challenge.update(challenge_params)
      redirect_to challenge_path(@challenge), notice: "Challenge updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end
  def destroy
    authorize @challenge
    @challenge.destroy
    redirect_to challenges_path, notice: "Challenge deleted."
  end

  private
  def set_challenge
    @challenge = Challenge.find(params[:id])
  end

  def challenge_params
    params.require(:challenge).permit(:title, :goal_type, :goal_value, :starts_at, :ends_at, :active)
  end
end
