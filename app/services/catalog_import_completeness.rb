# How many of the Open Library Works selected for the reading scenario exist
# as books. The selected list is the captured snapshot in db/seeds, so this is
# kept separate from the synthetic scenario volumes. Failed imports stay
# missing; they are never replaced with placeholder books.
class CatalogImportCompleteness
  SNAPSHOT_PATH = Rails.root.join("db/seeds/open_library_catalog.json")

  Result = Data.define(:selected_count, :imported_count) do
    def missing_count
      selected_count - imported_count
    end
  end

  def initialize(snapshot_path: SNAPSHOT_PATH)
    @snapshot_path = Pathname.new(snapshot_path)
  end

  def completeness
    return Result.new(selected_count: 0, imported_count: 0) unless @snapshot_path.exist?

    selected_ids = selected_work_ids
    Result.new(selected_count: selected_ids.size, imported_count: imported_work_ids(selected_ids).size)
  end

  private

  # Work keys appear as "/works/OL123W" or "OL123W"; compare the bare ID.
  def selected_work_ids
    JSON.parse(@snapshot_path.read)
      .fetch("selected")
      .map { |entry| bare_work_id(entry.fetch("work_key")) }
      .uniq
  end

  def imported_work_ids(selected_ids)
    key_variants = selected_ids.flat_map { |id| [ id, "/works/#{id}" ] }

    Book
      .where("BTRIM(ol_work_key) IN (?)", key_variants)
      .pluck(:ol_work_key)
      .map { |key| bare_work_id(key) }
      .uniq
  end

  def bare_work_id(work_key)
    work_key.strip.split("/").last
  end
end
