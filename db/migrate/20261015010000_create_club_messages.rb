class CreateClubMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :club_messages do |t|
      t.references :book_club, null: false, foreign_key: true, index: false
      t.references :user, null: false, foreign_key: true
      t.text :body, null: false

      t.timestamps
    end

    add_index :club_messages, [ :book_club_id, :id ]
    add_check_constraint :club_messages, "char_length(body) <= 1000", name: "club_messages_body_length"
  end
end
