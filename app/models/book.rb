class Book < ApplicationRecord
  has_one_attached :cover_image

  validates :title, presence: true
  validates :author, presence: true

  has_many :user_books, dependent: :destroy
  has_many :users, through: :user_books
end
