class AddDeletedAtToClubMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :club_messages, :deleted_at, :datetime
    add_check_constraint :club_messages,
      "deleted_at IS NULL OR (parent_id IS NULL AND body = '')",
      name: "club_messages_deleted_post_state"
  end
end
