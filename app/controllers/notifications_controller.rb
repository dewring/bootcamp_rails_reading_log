class NotificationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_notification, only: :update

  def update
    authorize @notification, policy_class: NotificationPolicy
    @notification.mark_as_read!
    broadcast_notification_panel

    respond_to do |format|
      format.turbo_stream { head :no_content }
      format.html { redirect_to root_path }
    end
  end

  private

  def set_notification
    @notification = Noticed::Notification.find(params[:id])
  end

  def broadcast_notification_panel
    Turbo::StreamsChannel.broadcast_replace_to(
      current_user,
      :notifications,
      target: "notifications_panel",
      partial: "notifications/panel",
      locals: current_user.notification_panel_locals
    )
  end
end
