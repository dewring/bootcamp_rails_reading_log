class ReactionPolicy < ApplicationPolicy
  def show?
    target = reaction_target
    target&.persisted? && Pundit.policy!(user, target).show?
  end

  def create?
    user.present? && user.account_status == "active" && owner? && show?
  end

  def update?
    create?
  end

  def destroy?
    create?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      user.present? ? scope.where(user_id: user.id) : scope.none
    end
  end

  private

  def reaction_target
    record.book
  end
end
