class ChallengesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_challenge, only: [ :show ]

  def index
    authorize Challenge
    @challenges = policy_scope(Challenge).where(active: true)
  end

  def show
    authorize @challenge
  end

  private

  def set_challenge
    @challenge = Challenge.find(params[:id])
  end
end
