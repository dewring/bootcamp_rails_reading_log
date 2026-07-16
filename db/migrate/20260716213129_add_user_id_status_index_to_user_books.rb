class AddUserIdStatusIndexToUserBooks < ActiveRecord::Migration[8.1]
  def change
    remove_index :user_books, :user_id
    add_index :user_books, [ :user_id, :status ]
  end
end
