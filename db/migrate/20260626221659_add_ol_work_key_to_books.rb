class AddOlWorkKeyToBooks < ActiveRecord::Migration[8.1]
  def change
    add_column :books, :ol_work_key, :string
    add_index :books, :ol_work_key, unique: true
  end
end
