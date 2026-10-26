class NotificationPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def update?
    user.present? && record.recipient == user
  end
end
