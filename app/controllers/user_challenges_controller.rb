class UserChallengesController < ApplicationController
  rescue_from ActiveRecord::StaleObjectError, with: :challenge_update_conflicted

  before_action :authenticate_user!
  before_action :set_user_challenge, only: [ :destroy ]

  def create
    @challenge = Challenge.find(params[:user_challenge][:challenge_id])
    @user_challenge = current_user.user_challenges.find_or_initialize_by(challenge: @challenge)

    if @user_challenge.persisted? && @user_challenge.abandoned?
      @user_challenge.assign_attributes(status: :active, progress: 0)
    end

    authorize @user_challenge

    if @user_challenge.save
      redirect_to challenges_path, notice: "You joined the challenge."
    else
      redirect_to challenges_path, alert: @user_challenge.errors.full_messages.to_sentence
    end
  end

  def destroy
    authorize @user_challenge
    @user_challenge.update(status: :abandoned)
    redirect_to @user_challenge.challenge, notice: "You've left this challenge."
  end

  private

  def challenge_update_conflicted
    flash[:alert] = "Your challenge was updated by another process. Please try again."
    redirect_back(fallback_location: challenges_path)
  end

  def set_user_challenge
    @user_challenge = current_user.user_challenges.find(params[:id])
  end
end
