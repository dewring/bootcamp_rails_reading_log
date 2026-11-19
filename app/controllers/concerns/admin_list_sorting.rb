# "Updated / Name" sorting with an explicit direction for admin list
# workspaces (members and book clubs). Dates default to newest first and
# names to A–Z, matching the order each list showed before directions existed.
module AdminListSorting
  extend ActiveSupport::Concern

  ADMIN_LIST_SORTS = [ "updated", "name" ].freeze
  ADMIN_LIST_DIRECTIONS = [ "asc", "desc" ].freeze
  DEFAULT_ADMIN_LIST_DIRECTIONS = { "updated" => "desc", "name" => "asc" }.freeze

  private

  def select_admin_list_sort
    @sort = params[:sort].presence_in(ADMIN_LIST_SORTS) || "updated"
    @direction = params[:direction].presence_in(ADMIN_LIST_DIRECTIONS) || DEFAULT_ADMIN_LIST_DIRECTIONS.fetch(@sort)
  end

  # The id tiebreaker follows the same direction so equal values keep a stable order.
  def admin_list_order(name_columns)
    columns = @sort == "name" ? name_columns : [ :updated_at ]
    columns.push(:id).index_with(@direction.to_sym)
  end
end
