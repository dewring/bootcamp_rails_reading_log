module Admin::ListSortingHelper
  ADMIN_LIST_DIRECTION_LABELS = {
    "updated" => { "desc" => "Newest first", "asc" => "Oldest first" },
    "name" => { "asc" => "A–Z", "desc" => "Z–A" }
  }.freeze

  # Trigger text that names both the field and the direction, e.g. "Updated · Newest first".
  def admin_list_sort_label(sort, direction, name_label:)
    "#{admin_list_sort_group_label(sort, name_label)} · #{ADMIN_LIST_DIRECTION_LABELS.fetch(sort).fetch(direction)}"
  end

  # Menu groups for the shared admin sort menu; path_for builds each option's link.
  def admin_list_sort_groups(name_label:, current_sort:, current_direction:, &path_for)
    ADMIN_LIST_DIRECTION_LABELS.map do |sort, directions|
      options = directions.map do |direction, label|
        selected = sort == current_sort && direction == current_direction
        { label: label, path: path_for.call(sort, direction), selected: selected }
      end
      { label: admin_list_sort_group_label(sort, name_label), options: options }
    end
  end

  private

  def admin_list_sort_group_label(sort, name_label)
    sort == "name" ? name_label : "Updated"
  end
end
