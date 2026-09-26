module NotificationsHelper
  def notification_panel_locals
    current_user.notification_panel_locals
  end
end
