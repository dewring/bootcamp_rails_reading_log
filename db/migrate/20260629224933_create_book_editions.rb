class CreateBookEditions < ActiveRecord::Migration[8.1]
  def change
    create_table :book_editions do |t|
      t.references :book, null: false, foreign_key: true
      t.string :ol_edition_key, null: false
      t.string :isbn
      t.string :publisher
      t.string :publish_year
      t.integer :page_count
      t.string :language
      t.string :format
      t.timestamps
    end

    add_index :book_editions, :ol_edition_key, unique: true
    add_index :book_editions, :isbn
  end
end
