class BookClubLeaderboardSnapshot < ApplicationRecord
  belongs_to :book_club
  belongs_to :current_book, class_name: "Book", optional: true
end
