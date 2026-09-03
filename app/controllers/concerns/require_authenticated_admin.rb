module RequireAuthenticatedAdmin
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_user!
    include RequireAdmin
  end
end
