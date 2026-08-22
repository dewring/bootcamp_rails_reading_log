class AddCurrentBookAndReadingDeadlineToBookClubs < ActiveRecord::Migration[8.1]
  def change
    add_reference :book_clubs, :current_book, null: true, foreign_key: { to_table: :books }
    add_column :book_clubs, :reading_deadline, :date
  end
end
