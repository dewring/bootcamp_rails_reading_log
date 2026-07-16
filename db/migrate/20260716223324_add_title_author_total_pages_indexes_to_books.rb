class AddTitleAuthorTotalPagesIndexesToBooks < ActiveRecord::Migration[8.1]
  def change
    add_index :books, :title
    add_index :books, :author
    add_index :books, :total_pages
  end
end
