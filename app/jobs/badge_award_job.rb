class BadgeAwardJob < ApplicationJob
  include SemanticLogger::Loggable

  queue_as :default
  discard_on ActiveRecord::RecordNotFound

  def perform(user)
    logger.measure_info(
      "Awarding badges",
      payload: { user_id: user.id }
    ) do
      award(user, "first_session")      if first_session?(user)
      award(user, "week_streak")        if week_streak?(user)
      award(user, "bookworm")           if bookworm?(user)
      award(user, "challenge_complete") if challenge_complete?(user)
      award(user, "page_turner")        if page_turner?(user)
    end
  end

  private

  def first_session?(user)
    user.reading_sessions.exists?
  end

  def week_streak?(user)
    ReadingSession.current_streak(user) >= 7
  end

  def bookworm?(user)
    user.user_books.where(status: "finished").count >= 5
  end

  def challenge_complete?(user)
    user.user_challenges.where(status: "completed").exists?
  end

  def page_turner?(user)
    user.reading_sessions.sum(:pages_read) >= 500
  end

  def award(user, badge_type)
    badge = Badge.find_by!(badge_type: badge_type)
    UserBadge.find_or_create_by!(user: user, badge: badge) do |ub|
      ub.awarded_at = Time.current
    end
  rescue ActiveRecord::RecordNotUnique
    # already awarded by a concurrent run of this job - the database unique
    # index on [user_id, badge_id] is what actually prevents the duplicate
  end
end
