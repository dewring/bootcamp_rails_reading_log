module DiscussionReactionPanels
  extend ActiveSupport::Concern

  private

  # Both callers authenticate and authorize discuss? before preparing panels.
  def message_reaction_panel_locals(messages)
    visible = messages.reject(&:deleted?)
    ids = visible.map(&:id)
    types = ReactionType.order(:id).to_a
    counts = ClubMessageReaction.eligible.where(club_message_id: ids).group(:club_message_id, :kind).count
    selections = policy_scope(ClubMessageReaction.where(club_message_id: ids)).index_by(&:club_message_id)
    can_react = current_user.account_status == "active"

    visible.to_h do |message|
      totals = types.to_h { |type| [ type.key, counts.fetch([ message.id, type.key ], 0) ] }
      [ message.id, { target: message, types: types, counts: totals, selected: selections[message.id], can_react: can_react, errors: [] } ]
    end
  end

  def render_message_reaction_panels(panels)
    panels.transform_values do |locals|
      render_to_string(partial: "reactions/panel", formats: [ :html ], locals: locals)
    end
  end
end
