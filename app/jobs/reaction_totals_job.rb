class ReactionTotalsJob < ApplicationJob
  queue_as :default
  # Keep worker broadcasts for the same target in order.
  limits_concurrency to: 1, key: ->(target_type, target_id) { "#{target_type}:#{target_id}" }

  TARGET_MODELS = { "Book" => Book, "Review" => Review, "ClubMessage" => ClubMessage }.freeze

  def perform(target_type, target_id)
    target = TARGET_MODELS.fetch(target_type).find_by(id: target_id)
    return unless target
    return if target.is_a?(ClubMessage) && target.deleted?

    locals = {
      target: target,
      types: ReactionType.order(:id).to_a,
      counts: target.reactions.eligible.group(:kind).count
    }
    if target.is_a?(ClubMessage)
      ClubDiscussionChannel.broadcast_to(target.book_club, {
        type: "reactions.updated", message_id: target.id,
        counts_html: ApplicationController.render(partial: "reactions/counts", locals: locals)
      })
    else
      book_id = target.is_a?(Book) ? target.id : target.book_id
      Turbo::StreamsChannel.broadcast_replace_to("book_reactions_#{book_id}",
        target: ActionView::RecordIdentifier.dom_id(target, :reaction_counts),
        partial: "reactions/counts", locals: locals)
    end
  end
end
