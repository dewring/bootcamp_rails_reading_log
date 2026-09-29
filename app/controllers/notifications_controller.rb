class NotificationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_notification, only: :update

  def update
    authorize @notification, policy_class: NotificationPolicy
    @notification.mark_as_read!

    respond_to do |format|
      format.turbo_stream do
        render template: "notifications/update",
          locals: { notification: @notification }
      end
      format.html { redirect_to root_path }
    end
  end

  private

  def set_notification
    @notification = Noticed::Notification.find(params[:id])
  end
end
