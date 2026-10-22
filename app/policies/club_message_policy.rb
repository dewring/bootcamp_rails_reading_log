class ClubMessagePolicy < ApplicationPolicy
  def index?
    club_policy.discuss?
  end

  def show?
    club_policy.discuss?
  end

  def create?
    return false if record.deleted?
    return false if record.parent && record.parent.deleted?

    club_policy.post_message?
  end

  def update?
    !record.deleted? && club_policy.post_message? && owner?
  end

  def destroy?
    return false unless user

    admin? || club_policy.manage? || (club_policy.post_message? && owner?)
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user
      return scope.all if user.admin?

      scope.where(book_club_id: user.book_club_memberships.select(:book_club_id))
    end
  end

  private

  def club_policy
    BookClubPolicy.new(user, record.book_club)
  end
end
