module NotificationPanel
  extend ActiveSupport::Concern

  def notification_panel_locals
    {
      notifications: notification_panel_notifications,
      unread_count: unread_notifications_count
    }
  end

  private

  def notification_panel_notifications
    notifications
      .includes(event: :record)
      .newest_first
      .limit(20)
  end

  def unread_notifications_count
    notifications.unread.count
  end
end
