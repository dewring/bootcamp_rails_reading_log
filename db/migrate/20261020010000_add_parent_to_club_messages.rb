class AddParentToClubMessages < ActiveRecord::Migration[8.1]
  def change
    add_reference :club_messages, :parent, null: true, index: false, foreign_key: { to_table: :club_messages }
    add_index :club_messages, [ :parent_id, :id ]
    add_check_constraint :club_messages, "parent_id IS NULL OR parent_id <> id", name: "club_messages_parent_not_self"
  end
end
