class NotificationPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def update?
    user.present? && record.recipient == user
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      user.present? ? scope.where(recipient: user) : scope.none
    end
  end
end
