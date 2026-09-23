class NotificationsPanel
  def initialize(user)
    @user = user
  end

  def locals
    {
      notifications: notifications,
      unread_count: unread_count
    }
  end

  private

  attr_reader :user

  def notifications
    user.notifications
      .includes(event: :record)
      .newest_first
      .limit(20)
  end

  def unread_count
    user.notifications.unread.count
  end
end
