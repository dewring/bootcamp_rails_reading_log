class AddUserIdBookIdIndexToReadingSessions < ActiveRecord::Migration[8.1]
  def change
    add_index :reading_sessions, [ :user_id, :book_id ]
  end
end
