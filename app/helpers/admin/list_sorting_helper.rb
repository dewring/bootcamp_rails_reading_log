module Admin::ListSortingHelper
  ADMIN_LIST_DIRECTION_LABELS = {
    date: { "desc" => "Newest first", "asc" => "Oldest first" },
    text: { "asc" => "A–Z", "desc" => "Z–A" },
    count: { "desc" => "Most first", "asc" => "Fewest first" }
  }.freeze

  # Trigger text that names both the field and the direction, e.g. "Updated · Newest first".
  def admin_list_sort_label(sort_fields, sort, direction)
    label, kind = sort_fields.fetch(sort)
    "#{label} · #{ADMIN_LIST_DIRECTION_LABELS.fetch(kind).fetch(direction)}"
  end

  # Menu groups for the shared admin sort menu; path_for builds each option's link.
  def admin_list_sort_groups(sort_fields, current_sort:, current_direction:, &path_for)
    sort_fields.map do |sort, (label, kind)|
      options = ADMIN_LIST_DIRECTION_LABELS.fetch(kind).map do |direction, direction_label|
        selected = sort == current_sort && direction == current_direction
        { label: direction_label, path: path_for.call(sort, direction), selected: selected }
      end
      { label: label, options: options }
    end
  end
end
