class UserChallengePolicy < ApplicationPolicy
  def create?
    user.present? && owner? && not_already_enrolled?
  end

  def destroy?
    owner?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user
      scope.where(user: user)
    end
  end

  private

  def not_already_enrolled?
    return true if record.persisted? || record.challenge.blank?
    !user.user_challenges.where(challenge: record.challenge).where.not(status: :abandoned).exists?
  end
end
