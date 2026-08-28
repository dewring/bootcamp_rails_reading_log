class AddBookClubMembershipsCountToBookClubs < ActiveRecord::Migration[8.1]
  def change
    add_column :book_clubs, :book_club_memberships_count, :integer, null: false, default: 0
  end
end
