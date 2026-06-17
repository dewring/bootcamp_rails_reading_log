class CreateReadingSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :reading_sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :book, null: false, foreign_key: true
      t.date :read_on, null: false
      t.integer :pages_read, null: false
      t.text :notes

      t.timestamps
    end
  end
end
