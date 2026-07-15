class RemoveUserIdIndexFromReadingSessions < ActiveRecord::Migration[8.1]
  def change
    remove_index :reading_sessions, :user_id
  end
end
