class AddAccountStatusToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :account_status, :string, null: false, default: "active"
    add_index :users, :account_status
    add_check_constraint :users, "account_status IN ('active', 'invited', 'suspended')", name: "users_account_status_valid"
  end
end
