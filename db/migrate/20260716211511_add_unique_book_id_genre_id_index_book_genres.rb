class AddUniqueBookIdGenreIdIndexBookGenres < ActiveRecord::Migration[8.1]
  def change
    remove_index :book_genres, :book_id
    add_index :book_genres, [ :book_id, :genre_id ], unique: true
  end
end
