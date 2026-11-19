# Field + direction sorting for admin list workspaces. Each list passes its
# sort fields as { "param" => ["Menu label", kind] }; the first field is the
# default. Dates default to newest first, text to A–Z, and counts to most first.
module AdminListSorting
  extend ActiveSupport::Concern

  ADMIN_LIST_DIRECTIONS = [ "asc", "desc" ].freeze
  DEFAULT_ADMIN_LIST_DIRECTIONS = { date: "desc", text: "asc", count: "desc" }.freeze

  private

  def select_admin_list_sort(sort_fields)
    @sort_fields = sort_fields
    @sort = params[:sort].presence_in(sort_fields.keys) || sort_fields.keys.first
    _label, kind = sort_fields.fetch(@sort)
    @direction = params[:direction].presence_in(ADMIN_LIST_DIRECTIONS) || DEFAULT_ADMIN_LIST_DIRECTIONS.fetch(kind)
  end

  # The id tiebreaker follows the same direction so equal values keep a stable order.
  def admin_list_order(columns)
    [ *columns, :id ].index_with(@direction.to_sym)
  end
end
