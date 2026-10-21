class ClubDiscussionChannel < ApplicationCable::Channel
  MESSAGE_LIMIT = 20
  MESSAGE_PERIOD = 1.minute

  def subscribed
    @book_club = BookClub.find_by(id: params[:book_club_id])

    if discussion_allowed?
      stream_for @book_club, coder: ActiveSupport::JSON do |event|
        transmit_discussion_event(event)
      end
    else
      reject
    end
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

      transmit event
    else
      revoke_discussion_access
    end
  end

  def revoke_discussion_access
    @access_revoked = true
    stop_all_streams
    transmit({ type: "access.revoked" })
  end
end
