class ClubDiscussionChannel < ApplicationCable::Channel
  MESSAGE_LIMIT = 20
  MESSAGE_PERIOD = 1.minute
  HEARTBEAT_MINIMUM_INTERVAL = 5.seconds
  TYPING_MINIMUM_INTERVAL = 1.second
  TYPING_EXPIRY = 3.seconds

  def subscribed
    @book_club = BookClub.find_by(id: params[:book_club_id])

    if discussion_allowed?
      stream_for @book_club, coder: ActiveSupport::JSON do |event|
        transmit_discussion_event(event)
      end
      @presence_connection_token = SecureRandom.hex(16)
      renew_presence(initial_snapshot: true)
    else
      reject
    end
  end

  def unsubscribed
    @access_revoked = true
    remove_presence_connection
  end

  def heartbeat(_data = {})
    return if @access_revoked || !@presence_connection_token
    return revoke_discussion_access unless discussion_allowed?

    renew_presence
  end

  def typing(_data = {})
    return if @access_revoked || !@presence_connection_token
    return revoke_discussion_access unless discussion_allowed?

    user = User.find_by(id: current_user.id)
    return unless BookClubPolicy.new(user, @book_club).post_message?

    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    return if @last_typing_event_at && now - @last_typing_event_at < TYPING_MINIMUM_INTERVAL.to_i

    @last_typing_event_at = now
    self.class.broadcast_to(@book_club, {
      type: "typing.started",
      user_id: user.id,
      connection_token: @presence_connection_token,
      generated_at: Time.current.iso8601(6)
    })
  end

  def post_message(data)
    save_discussion_message(data, reply: false)
  end

  def post_reply(data)
    save_discussion_message(data, reply: true)
  end

  def update_message(data)
    return if @access_revoked
    return revoke_discussion_access unless discussion_allowed?

    request_id = request_id_from(data)
    return unless request_id

    message = discussion_message_from(data)
    unless message
      transmit({ type: "edit.rejected", request_id: request_id, error: "not_found" })
      return
    end

    user = User.find_by(id: current_user.id)
    body = data["body"] if data["body"].is_a?(String)
    response = message.with_lock { edit_message_response(message, user, body, request_id) }
    transmit response
  rescue ActiveRecord::RecordNotFound
    transmit({ type: "edit.rejected", request_id: request_id, error: "not_found" })
  end

  def delete_message(data)
    return if @access_revoked
    return revoke_discussion_access unless discussion_allowed?

    request_id = request_id_from(data)
    return unless request_id

    message = discussion_message_from(data)
    unless message
      transmit({ type: "delete.rejected", request_id: request_id, error: "not_found" })
      return
    end

    user = User.find_by(id: current_user.id)
    unless ClubMessagePolicy.new(user, message).destroy?
      transmit({ type: "delete.rejected", request_id: request_id, error: "forbidden" })
      return
    end

    payload = message.remove_from_discussion!
    transmit({ type: "delete.saved", request_id: request_id, message: payload, total_posts: @book_club.club_messages.visible_posts.count })
  rescue ActiveRecord::RecordNotFound
    transmit({ type: "delete.rejected", request_id: request_id, error: "not_found" })
  end

  private

  def renew_presence(initial_snapshot: false)
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    return if @last_presence_renewal_at && now - @last_presence_renewal_at < HEARTBEAT_MINIMUM_INTERVAL.to_i

    @last_presence_renewal_at = now
    member_ids = Rails.configuration.x.club_presence.redis_pool.with do |redis|
      presence = ClubPresence.new(@book_club, redis: redis)
      if @book_club.book_club_memberships.exists?(user_id: current_user.id)
        presence.renew_connection(user_id: current_user.id, connection_token: @presence_connection_token)
      else
        presence.active_member_ids
      end
    end
    event = broadcast_presence_snapshot(member_ids)
    transmit_discussion_event(event.stringify_keys) if initial_snapshot
  rescue Redis::BaseError, ConnectionPool::TimeoutError => error
    Rails.logger.warn("Club presence unavailable for book club #{@book_club.id}: #{error.class}")
    transmit({ type: "presence.unavailable" })
  end

  def remove_presence_connection
    return unless @presence_connection_token

    connection_token = @presence_connection_token
    @presence_connection_token = nil
    member_ids = Rails.configuration.x.club_presence.redis_pool.with do |redis|
      presence = ClubPresence.new(@book_club, redis: redis)
      presence.remove_connection(user_id: current_user.id, connection_token: connection_token)
    end
    broadcast_presence_snapshot(member_ids) if BookClub.exists?(@book_club.id)
  rescue Redis::BaseError, ConnectionPool::TimeoutError => error
    Rails.logger.warn("Club presence cleanup failed for book club #{@book_club.id}: #{error.class}")
    self.class.broadcast_to(@book_club, { type: "presence.unavailable" })
  end

  def broadcast_presence_snapshot(member_ids)
    event = { type: "presence.snapshot", member_ids: member_ids, generated_at: Time.current.iso8601(6) }
    self.class.broadcast_to(@book_club, event)
    event
  end

  def presence_members(member_ids)
    @book_club.users.where(id: member_ids).order(:id).pluck(:id, :nickname).map do |id, nickname|
      { id: id, nickname: nickname }
    end
  end

  def discussion_message_from(data)
    message_id = data["message_id"]
    @book_club.club_messages.find_by(id: message_id) if message_id.is_a?(Integer) && message_id.positive?
  end

  def edit_message_response(message, user, body, request_id)
    unless ClubMessagePolicy.new(user, message).update?
      return { type: "edit.rejected", request_id: request_id, error: "forbidden" }
    end

    if message.update(body: body)
      { type: "edit.saved", request_id: request_id, message: message.discussion_payload }
    else
      { type: "edit.rejected", request_id: request_id, errors: message.errors.to_hash }
    end
  end

  def request_id_from(data)
    request_id = data["request_id"]
    request_id if request_id.is_a?(String) && request_id.length.between?(1, 64)
  end

  def save_discussion_message(data, reply:)
    return if @access_revoked
    return revoke_discussion_access unless discussion_allowed?

    request_id = request_id_from(data)
    return unless request_id

    event_prefix = reply ? "reply" : "post"
    parent = reply_parent(data["parent_id"]) if reply
    if reply && parent.nil?
      transmit({ type: "reply.rejected", request_id: request_id, error: "not_found" })
      return
    end

    user = User.find_by(id: current_user.id)
    body = data["body"] if data["body"].is_a?(String)
    message = @book_club.club_messages.build(user: user, body: body, parent: parent)

    unless ClubMessagePolicy.new(user, message).create?
      transmit({ type: "#{event_prefix}.rejected", request_id: request_id, error: "forbidden" })
      return
    end

    if message_rate_limited?(user)
      transmit({ type: "#{event_prefix}.rejected", request_id: request_id, error: "rate_limited" })
      return
    end

    if persist_discussion_message(message)
      transmit({ type: "#{event_prefix}.saved", request_id: request_id, message: message.discussion_payload, total_posts: @book_club.club_messages.visible_posts.count })
    else
      transmit({ type: "#{event_prefix}.rejected", request_id: request_id, errors: message.errors.to_hash })
    end
  end

  def persist_discussion_message(message)
    if message.parent
      message.parent.with_lock { message.save }
    else
      message.save
    end
  end

  def reply_parent(parent_id)
    return unless parent_id.is_a?(Integer) && parent_id.positive?

    @book_club.club_messages.top_level.find_by(id: parent_id, deleted_at: nil)
  end

  def message_rate_limited?(user)
    # HTTP middleware cannot count Cable actions, so reuse Rack::Attack's cache counter here.
    count = Rack::Attack.cache.count("club-discussion/messages/user/#{user.id}", MESSAGE_PERIOD)
    count > MESSAGE_LIMIT
  end

  def discussion_allowed?
    return false unless @book_club && current_user

    user = User.find_by(id: current_user.id)
    BookClub.exists?(@book_club.id) && BookClubPolicy.new(user, @book_club).discuss?
  end

  def transmit_discussion_event(event)
    return if @access_revoked

    if discussion_allowed?
      return if event["type"] == "access.recheck"

      if event["type"] == "presence.snapshot"
        event = event.except("member_ids").merge("members" => presence_members(event.fetch("member_ids")))
      elsif event["type"] == "typing.started"
        return if Time.iso8601(event.fetch("generated_at")) <= Time.current - TYPING_EXPIRY

        member = presence_members([ event.fetch("user_id") ]).first
        return unless member

        event = event.except("user_id").merge("member" => member)
      end
      transmit event
    else
      revoke_discussion_access
    end
  end

  def revoke_discussion_access
    @access_revoked = true
    stop_all_streams
    remove_presence_connection
    transmit({ type: "access.revoked" })
  end
end
