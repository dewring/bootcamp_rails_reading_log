require "test_helper"

class ReactionTotalsJobTest < ActiveJob::TestCase
  include ActionCable::TestHelper

  def queue_adapter_for_test
    ActiveJob::QueueAdapters::TestAdapter.new
  end

  setup do
    @reader = users(:leika)
    @book = Book.create!(title: "Live reaction book", author: "Test author")
    @review = @book.reviews.create!(user: users(:admin), rating: 4, body: "A private-to-the-author draft is elsewhere")
    @club = BookClub.create!(name: "Live reaction discussion")
    @message = @club.club_messages.create!(user: @reader, body: "A message")
  end

  test "book broadcasts replace only aggregate counts on that books stream" do
    @book.reactions.create!(user: @reader, kind: "like")
    @book.reactions.create!(user: users(:jaina), kind: "love")
    users(:jaina).update!(account_status: "suspended")
    reaction_types(:like).update!(enabled: false)

    streams = capture_turbo_stream_broadcasts("book_reactions_#{@book.id}") do
      ReactionTotalsJob.perform_now("Book", @book.id)
    end

    assert_equal 1, streams.size
    stream = streams.first
    assert_equal "replace", stream["action"]
    assert_equal "reaction_counts_book_#{@book.id}", stream["target"]
    assert_equal "👍 Like: 1", stream.at_css("[data-reaction-kind='like']").text
    assert_equal "❤️ Love: 0", stream.at_css("[data-reaction-kind='love']").text
    assert_public_counts_only(stream)
    assert_no_turbo_stream_broadcasts("book_reactions_#{books(:pragmatic).id}") do
      ReactionTotalsJob.perform_now("Book", @book.id)
    end
  end

  test "review broadcasts use the parent books stream and an independent review counts target" do
    @review.reactions.create!(user: @reader, kind: "wow")
    @book.reactions.create!(user: @reader, kind: "love")

    streams = capture_turbo_stream_broadcasts("book_reactions_#{@book.id}") do
      ReactionTotalsJob.perform_now("Review", @review.id)
    end

    assert_equal 1, streams.size
    assert_equal "reaction_counts_review_#{@review.id}", streams.first["target"]
    assert_equal "😮 Wow: 1", streams.first.at_css("[data-reaction-kind='wow']").text
    assert_equal "❤️ Love: 0", streams.first.at_css("[data-reaction-kind='love']").text
    assert_public_counts_only(streams.first)
  end

  test "post and reply broadcasts contain aggregate HTML on their authorized Discussion channel" do
    reply = @club.club_messages.create!(parent: @message, user: @reader, body: "A reply")
    [ @message, reply ].each do |message|
      message.reactions.create!(user: @reader, kind: "laugh")
      events = capture_broadcasts(ClubDiscussionChannel.broadcasting_for(@club)) do
        ReactionTotalsJob.perform_now("ClubMessage", message.id)
      end

      assert_equal 1, events.size
      event = events.first
      assert_equal [ "counts_html", "message_id", "type" ], event.keys.sort
      assert_equal "reactions.updated", event.fetch("type")
      assert_equal message.id, event.fetch("message_id")
      html = Nokogiri::HTML.fragment(event.fetch("counts_html"))
      assert_equal "😂 Laugh: 1", html.at_css("#reaction_counts_club_message_#{message.id} [data-reaction-kind='laugh']").text
      assert_public_counts_only(html)
    end
  end

  test "catalog additions and relabelling appear in aggregate HTML without changing reactions" do
    type = ReactionType.create!(key: "celebrate", label: "Celebrate", emoji: "🎉", enabled: true)
    reaction = @book.reactions.create!(user: @reader, kind: type.key)
    before = reaction.attributes
    type.update!(label: "Celebration", emoji: "🙌🏽")

    streams = capture_turbo_stream_broadcasts("book_reactions_#{@book.id}") do
      ReactionTotalsJob.perform_now("Book", @book.id)
    end

    assert_equal "🙌🏽 Celebration: 1", streams.first.at_css("[data-reaction-kind='celebrate']").text
    assert_equal before, reaction.reload.attributes
  end

  test "deleted targets and soft deleted posts do not broadcast" do
    @message.remove_from_discussion!
    assert_no_broadcasts(ClubDiscussionChannel.broadcasting_for(@club)) do
      ReactionTotalsJob.perform_now("ClubMessage", @message.id)
    end
    @review.destroy!
    @book.destroy!
    @message.destroy!

    assert_no_turbo_stream_broadcasts("book_reactions_#{@book.id}") do
      ReactionTotalsJob.perform_now("Book", @book.id)
      ReactionTotalsJob.perform_now("Review", @review.id)
    end
    assert_no_broadcasts(ClubDiscussionChannel.broadcasting_for(@club)) do
      ReactionTotalsJob.perform_now("ClubMessage", @message.id)
    end
  end

  test "only jobs for the same concrete target share a queue concurrency key" do
    first = ReactionTotalsJob.new("Book", @book.id)
    retry_job = ReactionTotalsJob.new("Book", @book.id)
    other_book = ReactionTotalsJob.new("Book", @book.id + 1)
    same_id_review = ReactionTotalsJob.new("Review", @book.id)

    assert_equal first.concurrency_key, retry_job.concurrency_key
    assert_not_equal first.concurrency_key, other_book.concurrency_key
    assert_not_equal first.concurrency_key, same_id_review.concurrency_key
  end

  test "committed eligibility changes and account deletion broadcast fresh surviving book totals" do
    @book.reactions.create!(user: @reader, kind: "like")
    [ [ "suspended", "👍 Like: 0" ], [ "active", "👍 Like: 1" ] ].each do |status, expected|
      streams = capture_turbo_stream_broadcasts("book_reactions_#{@book.id}") do
        perform_enqueued_jobs(only: ReactionTotalsJob) { @reader.update!(account_status: status) }
      end
      assert_equal 1, streams.size
      assert_equal expected, streams.first.at_css("[data-reaction-kind='like']").text
    end

    streams = capture_turbo_stream_broadcasts("book_reactions_#{@book.id}") do
      perform_enqueued_jobs(only: ReactionTotalsJob) { MemberAccountDeletion.new(member: @reader).delete_account }
    end

    assert_equal 1, streams.size
    assert_equal "👍 Like: 0", streams.first.at_css("[data-reaction-kind='like']").text
  end

  private

  def assert_public_counts_only(html)
    assert_empty html.css("form, button, [aria-pressed], [data-reaction-selection], turbo-frame")
    assert_not_includes html.to_html, @reader.email
    assert_not_includes html.to_html, @reader.nickname
  end
end
