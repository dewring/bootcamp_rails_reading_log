class Admin::ReportPolicy < ApplicationPolicy
  def show?
    admin?
  end
end
