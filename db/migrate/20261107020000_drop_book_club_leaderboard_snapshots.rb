class DropBookClubLeaderboardSnapshots < ActiveRecord::Migration[8.1]
  def change
    drop_table :book_club_leaderboard_snapshots do |t|
      t.references :book_club, null: false, index: { unique: true }, foreign_key: { on_delete: :cascade }
      t.references :current_book, foreign_key: { to_table: :books, on_delete: :nullify }
      t.bigint :leader_user_ids, array: true, default: [], null: false,
        comment: "Historical IDs for set comparison, not a live user association; former or deleted readers remain until the next snapshot."
      t.timestamps
    end
  end
end
