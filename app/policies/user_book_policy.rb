class UserBookPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    owner?
  end

  def create?
    user.present? && owner? && not_already_logged?
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

      scope.where(user: user)
    end
  end

  private

  def not_already_logged?
    return true if record.persisted? || record.book.blank?

    !user.user_books.exists?(book: record.book)
  end
end
