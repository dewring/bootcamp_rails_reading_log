class AddDescriptionAndSubjectsToBooks < ActiveRecord::Migration[8.1]
  def change
    add_column :books, :description, :text
    add_column :books, :subjects, :text
  end
end
