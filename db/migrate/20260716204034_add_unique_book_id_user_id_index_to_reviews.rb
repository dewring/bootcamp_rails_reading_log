class AddUniqueBookIdUserIdIndexToReviews < ActiveRecord::Migration[8.1]
  def change
    remove_index :reviews, :book_id
    remove_index :reviews, :user_id
    add_index :reviews, [ :book_id, :user_id ], unique: true
  end
end
