module RequireAdmin
  extend ActiveSupport::Concern

  included do
    before_action :require_admin!
  end

  private

  def require_admin!
    unless current_user&.admin?
      if request.format.json?
        render json: { error: "Forbidden" }, status: 403
      else
        redirect_to root_path, alert: "Not authorized."
      end
    end
  end
end
