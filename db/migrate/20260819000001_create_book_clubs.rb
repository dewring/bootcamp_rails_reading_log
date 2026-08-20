class CreateBookClubs < ActiveRecord::Migration[8.1]
  def change
    create_table :book_clubs do |t|
      t.string :name, null: false
      t.text :description

      t.timestamps
    end

    create_table :book_club_memberships do |t|
      t.references :book_club, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :role, null: false, default: "member"

      t.timestamps
    end

    add_index :book_club_memberships, [ :book_club_id, :user_id ], unique: true
  end
end
