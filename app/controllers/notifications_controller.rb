class NotificationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_notification, only: :update

  def index
    authorize Noticed::Notification, policy_class: NotificationPolicy

    @notifications = notification_scope
    @unread_count = unread_notification_count
  end

  def update
    authorize @notification, policy_class: NotificationPolicy
    @notification.mark_as_read!
    broadcast_notification_panel

    respond_to do |format|
      format.turbo_stream { head :no_content }
      format.html { redirect_to notifications_path }
    end
  end

  private

  def set_notification
    @notification = Noticed::Notification.find(params[:id])
  end

  def notification_scope
    policy_scope(Noticed::Notification, policy_scope_class: NotificationPolicy::Scope)
      .includes(event: :record)
      .newest_first
      .limit(20)
  end

  def unread_notification_count
    current_user.notifications.unread.count
  end

  def broadcast_notification_panel
    Turbo::StreamsChannel.broadcast_replace_to(
      current_user,
      :notifications,
      target: "notifications_panel",
      partial: "notifications/panel",
      locals: { notifications: notification_scope, unread_count: unread_notification_count }
    )
  end
end
