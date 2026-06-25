class ReadingSessionPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    record.user == user || user.admin?
  end

  def create?
    user.present?
  end

  def update?
    record.user == user
  end

  def destroy?
    record.user == user
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if user.admin?
        scope.all
      else
        scope.where(user: user)
      end
    end
  end
end
