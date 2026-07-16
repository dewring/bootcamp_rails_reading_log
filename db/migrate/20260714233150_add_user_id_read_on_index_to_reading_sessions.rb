class AddUserIdReadOnIndexToReadingSessions < ActiveRecord::Migration[8.1]
  def change
    add_index :reading_sessions, [ :user_id, :read_on ]
  end
end
