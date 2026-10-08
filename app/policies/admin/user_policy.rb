class Admin::UserPolicy < ApplicationPolicy
  def index?
    admin?
  end

  def create?
    admin?
  end

  def update?
    admin?
  end

  def update_status?
    admin? && !record.admin? && record != user
  end

  def destroy?
    update_status? && record.book_club_memberships.none? { |membership| membership.role == "owner" }
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      user&.admin? ? scope.all : scope.none
    end
  end
end
