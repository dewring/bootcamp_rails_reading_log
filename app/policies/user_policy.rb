class UserPolicy < ApplicationPolicy
  def show?
    owner? || admin?
  end

  def create?
    true
  end

  def update?
    owner? || admin?
  end

  def destroy?
    owner? || admin?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user

      user.admin? ? scope.all : scope.where(id: user.id)
    end
  end
end
