class ReactionsController < ApplicationController
  before_action :authenticate_user!, only: [ :update, :destroy ]
  before_action :set_reaction_target

  rescue_from Pundit::NotAuthorizedError, with: -> { head :forbidden }
  rescue_from ActiveRecord::RecordInvalid, with: :render_invalid_selection

  def show
    authorize @reaction_target.reactions.build(user: current_user), :show?
    render_panel
  end

  def update
    selection.select_kind(kind: params.permit(:kind)[:kind])
    respond_to_selection
  end

  def destroy
    selection.clear_selection
    respond_to_selection
  end

  private

  def selection
    ReactionSelection.new(user: current_user, target: @reaction_target)
  end

  def respond_to_selection
    respond_to do |format|
      format.html { redirect_to selection_redirect_path, status: :see_other }
      format.turbo_stream { render_panel }
    end
  end

  def render_invalid_selection(error)
    render_panel(status: :unprocessable_entity, errors: error.record.errors.full_messages)
  end

  def render_panel(status: :ok, errors: [])
    response.headers["Cache-Control"] = "no-store"
    counts = @reaction_target.reactions.eligible.group(:kind).count
    selected = policy_scope(@reaction_target.reactions).first
    types = ReactionType.order(:id).to_a
    panel = { target: @reaction_target, types: types, counts: counts, selected: selected, errors: errors }

    respond_to do |format|
      format.html { render partial: "reactions/panel", locals: panel, status: status }
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          helpers.dom_id(@reaction_target, :reaction_panel), partial: "reactions/panel", locals: panel
        ), status: status
      end
    end
  end
end
