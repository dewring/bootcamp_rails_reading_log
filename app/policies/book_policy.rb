class BookPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  def discover?
    user.present?
  end

  def search?
    user.present?
  end

  def import?
    user.present?
  end

  def most_recent_session?
    user.present?
  end

  def create?
    admin?
  end

  def update?
    admin?
  end

  def destroy?
    admin?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.all
    end
  end
end
