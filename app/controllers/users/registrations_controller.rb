module Users
  class RegistrationsController < Devise::RegistrationsController
    protected

    def account_update_params
      super.except(:email, "email")
    end

    def update_resource(resource, params)
      filtered_params = params.to_h.symbolize_keys.except(:email)
      remove_avatar = ActiveModel::Type::Boolean.new.cast(filtered_params.delete(:remove_avatar))

      if filtered_params[:password].present? || filtered_params[:password_confirmation].present?
        updated = resource.update_with_password(filtered_params)
      else
        updated = resource.update(filtered_params.except(:current_password, :password, :password_confirmation))
      end

      resource.avatar.purge if updated && remove_avatar

      updated
    end

    def after_update_path_for(_resource)
      edit_user_registration_path
    end
  end
end
