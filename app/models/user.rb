class User < ApplicationRecord
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

  has_one :reading_metric

  def admin?
    role == "admin"
  end
end
