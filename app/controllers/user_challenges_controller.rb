class UserChallengesController < ApplicationController
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
      redirect_to @challenge, notice: "Enrolled!"
    else
      redirect_to @challenge, alert: @user_challenge.errors.full_messages.to_sentence
    end
  end

  def destroy
    authorize @user_challenge
    @user_challenge.update(status: :abandoned)
    redirect_to @user_challenge.challenge, notice: "You've left this challenge."
  end

  private

  def set_user_challenge
    @user_challenge = current_user.user_challenges.find(params[:id])
  end
end
