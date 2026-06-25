class ReviewPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  def create?
    user.present? && owner? && not_already_reviewed?
  end

  def update?
    owner?
  end

  def destroy?
    owner?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.all
    end
  end

  private

  def not_already_reviewed?
    return true if record.persisted? || record.book.blank?

    !user.reviews.exists?(book: record.book)
  end
end
