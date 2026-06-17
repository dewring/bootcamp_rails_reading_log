class ReadingSession < ApplicationRecord
  belongs_to :user
  belongs_to :book

  validates :read_on, presence: true
  validates :pages_read, presence: true, numericality: { greater_than: 0 }

  def new
    @reading_session = @book.reading_sessions.build
  end
  def create
    @reading_session = @book.reading_sessions.build
  end
end
