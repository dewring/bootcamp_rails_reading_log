class WebhookEndpointsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_webhook_endpoint, only: [ :destroy ]

  def index
    authorize WebhookEndpoint
    @webhook_endpoints = policy_scope(WebhookEndpoint)
    @webhook_endpoint = current_user.webhook_endpoints.build
  end

  def create
    plain_secret = SecureRandom.hex(32)
    @webhook_endpoint = current_user.webhook_endpoints.build(webhook_endpoint_params)
    @webhook_endpoint.secret_digest = plain_secret

    authorize @webhook_endpoint

    if @webhook_endpoint.save
      flash[:plain_secret] = plain_secret
      redirect_to webhook_endpoints_path
    else
      @webhook_endpoints = policy_scope(WebhookEndpoint)
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @webhook_endpoint
    @webhook_endpoint.destroy
    redirect_to webhook_endpoints_path, notice: "Webhook endpoint removed."
  end

  private

  def set_webhook_endpoint
    @webhook_endpoint = current_user.webhook_endpoints.find(params[:id])
  end

  def webhook_endpoint_params
    params.require(:webhook_endpoint).permit(:url, :active).merge(events: [ "challenge_completed" ])
  end
end
