class AddUserIdStatusIndexToUserChallenges < ActiveRecord::Migration[8.1]
  def change
    add_index :user_challenges, [ :user_id, :status ]
  end
end
