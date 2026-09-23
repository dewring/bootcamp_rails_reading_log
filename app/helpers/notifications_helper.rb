module NotificationsHelper
  def notification_panel_notifications
    current_user.notifications
      .includes(event: :record)
      .newest_first
      .limit(20)
  end

  def notification_panel_unread_count
    current_user.notifications.unread.count
  end
end
