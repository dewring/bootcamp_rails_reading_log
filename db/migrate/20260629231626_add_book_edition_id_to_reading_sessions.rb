class AddBookEditionIdToReadingSessions < ActiveRecord::Migration[8.1]
  def change
    add_reference :reading_sessions, :book_edition, null: true, foreign_key: true
  end
end
