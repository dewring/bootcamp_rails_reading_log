class ReadingSessionPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    owner? || admin?
  end

  def create?
    user.present?
  end

  def update?
    owner?
  end

  def destroy?
    owner?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user

      if user.admin?
        scope.all
      else
        scope.where(user: user)
      end
    end
  end
end
