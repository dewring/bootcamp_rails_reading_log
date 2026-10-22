class ClubPresence
  CONNECTION_EXPIRY = 45.seconds
  KEY_TTL = 90.seconds

  def initialize(book_club, redis:, namespace: "booknook:#{Rails.env}:club_presence")
    @book_club = book_club
    @redis = redis
    @key = "#{namespace}:#{book_club.id}"
  end

  def renew_connection(user_id:, connection_token:)
    connection_snapshot do |transaction, renewed_at|
      transaction.zadd(@key, renewed_at, "#{user_id}:#{connection_token}")
      transaction.expire(@key, KEY_TTL.to_i)
    end
  end

  def remove_connection(user_id:, connection_token:)
    connection_snapshot do |transaction|
      transaction.zrem(@key, "#{user_id}:#{connection_token}")
    end
  end

  def active_member_ids
    connection_snapshot
  end

  private

  def connection_snapshot
    now = Time.current.to_f
    results = @redis.multi do |transaction|
      transaction.zremrangebyscore(@key, "-inf", now - CONNECTION_EXPIRY.to_i)
      yield(transaction, now) if block_given?
      transaction.zrange(@key, 0, -1)
    end

    user_ids = results.last.map { |entry| entry.split(":", 2).first.to_i }.uniq
    @book_club.book_club_memberships.where(user_id: user_ids).distinct.pluck(:user_id)
  end
end
