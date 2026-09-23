module NotificationsHelper
  def notification_panel_locals
    NotificationsPanel.new(current_user).locals
  end
end
