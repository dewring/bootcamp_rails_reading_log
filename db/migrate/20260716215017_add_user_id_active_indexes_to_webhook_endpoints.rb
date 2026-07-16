class AddUserIdActiveIndexesToWebhookEndpoints < ActiveRecord::Migration[8.1]
  def change
    remove_index :webhook_endpoints, :user_id
    add_index :webhook_endpoints, :user_id, where: "active = true", name: "index_webhook_endpoints_on_user_id_and_active_true"
    add_index :webhook_endpoints, [ :user_id, :active ]
  end
end
