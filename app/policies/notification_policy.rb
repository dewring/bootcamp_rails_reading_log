class NotificationPolicy < ApplicationPolicy
  def update?
    user.present? && record.recipient == user
  end
end
