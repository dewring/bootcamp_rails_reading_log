class AddActiveIndexToUserChallenges < ActiveRecord::Migration[8.1]
  def change
    remove_index :user_challenges, :user_id
    add_index :user_challenges, :user_id, where: "status = 'active'", name: "index_user_challenges_on_user_id_and_status_active"
  end
end
