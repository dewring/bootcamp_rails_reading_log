class BookClubPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  def create?
    user.present?
  end

  def join?
    user.present? && !member?
  end

  def leave?
    member? && !manage?
  end

  def manage?
    return false unless user

    record.book_club_memberships.exists?(user_id: user.id, role: "owner")
  end

  def destroy?
    manage?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.all
    end
  end

  private

  def member?
    user.present? && record.book_club_memberships.exists?(user_id: user.id)
  end
end
