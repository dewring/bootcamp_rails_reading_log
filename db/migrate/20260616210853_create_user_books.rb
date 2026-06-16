class CreateUserBooks < ActiveRecord::Migration[8.1]
  def change
    create_table :user_books do |t|
      t.references :user, null: false, foreign_key: true
      t.references :book, null: false, foreign_key: true
      t.string :status, null: false, default: "want_to_read"

      t.timestamps
    end

    add_index :user_books, [ :user_id, :book_id ], unique: true
  end
end
