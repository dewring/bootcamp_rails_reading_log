class CreateBooks < ActiveRecord::Migration[8.1]
  def change
    create_table :books do |t|
      t.string :title, null: false, default: ""
      t.string :author, null: false, default: ""
      t.integer :total_pages

      t.timestamps
    end
  end
end
