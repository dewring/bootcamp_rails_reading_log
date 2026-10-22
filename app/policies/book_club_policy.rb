class BookClubPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  def viewer_role
    if club_owner?
      "owner"
    elsif member?
      "member"
    elsif admin?
      "admin"
    else
      nil
    end
  end

  def discuss?
    admin_or_member?
  end

  def leaderboard?
    admin_or_member?
  end

  def post_message?
    member?
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

  def edit?
    manage?
  end

  def update?
    manage?
  end

  def manage?
    club_owner?
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

  def admin_or_member?
    admin? || member?
  end

  def club_owner?
    return false unless user

    record.book_club_memberships.exists?(user_id: user.id, role: "owner")
  end

  def member?
    user.present? && record.book_club_memberships.exists?(user_id: user.id)
  end
end
