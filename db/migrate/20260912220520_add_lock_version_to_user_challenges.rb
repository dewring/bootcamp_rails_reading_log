class AddLockVersionToUserChallenges < ActiveRecord::Migration[8.1]
  def change
    add_column :user_challenges, :lock_version, :integer, default: 0, null: false
  end
end
