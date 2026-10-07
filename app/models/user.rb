class User < ApplicationRecord
  include NotificationPanel

  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable
  validates :first_name, presence: true
  validates :last_name, presence: true
  validates :nickname, presence: true, uniqueness: true
  validates :role, inclusion: { in: %w[user admin] }

  has_many :user_books, dependent: :destroy
  has_many :books, through: :user_books
  has_many :reading_sessions
  has_many :reviews, dependent: :destroy
  has_many :user_challenges, dependent: :destroy
  has_many :challenges, through: :user_challenges
  has_many :webhook_endpoints, dependent: :destroy
  has_many :user_badges, dependent: :destroy
  has_many :badges, through: :user_badges
  has_many :book_club_memberships, dependent: :destroy
  has_many :book_clubs, through: :book_club_memberships
  has_many :notifications, as: :recipient, class_name: "Noticed::Notification", dependent: :destroy

  has_one :reading_metric
  has_one_attached :avatar

  validate :avatar_must_be_an_image, if: -> { avatar.attached? }
  validate :avatar_must_be_small_enough, if: -> { avatar.attached? }

  def admin?
    role == "admin"
  end

  private

  def avatar_must_be_an_image
    return if avatar.content_type.to_s.start_with?("image/")

    errors.add(:avatar, "must be an image")
  end

  def avatar_must_be_small_enough
    return if avatar.blob.byte_size <= 5.megabytes

    errors.add(:avatar, "must be smaller than 5 MB")
  end
end
