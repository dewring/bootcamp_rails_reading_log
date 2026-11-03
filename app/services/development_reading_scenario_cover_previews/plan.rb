class DevelopmentReadingScenarioCoverPreviews::Plan
  LIMIT = 12

  def initialize(snapshot:, books:)
    @snapshot = snapshot
    @books = books
  end

  def build_previews(missing_work_key: nil)
    pages = @snapshot.fetch("pages").to_h { |page| [ page.fetch("page"), JSON.parse(page.fetch("raw_body")).fetch("docs") ] }
    entries = @snapshot.fetch("selected").map do |selection|
      key = selection.fetch("work_key")
      cover_id = pages.fetch(selection.fetch("page")).fetch(selection.fetch("index"))["cover_i"]
      { "work_key" => key, "book_id" => @books.fetch(key).id,
        "cover_id" => cover_id.is_a?(Integer) && cover_id.positive? ? cover_id : nil }
    end
    missing = if missing_work_key
      entries.find { |entry| entry.fetch("work_key") == missing_work_key }
    else
      entries.reverse.find { |entry| entry["cover_id"].nil? && !attached?(entry) } || entries.reverse.find { |entry| !attached?(entry) }
    end
    unless missing && !attached?(missing)
      raise DevelopmentReadingScenarioCoverPreviews::PreviewError, "A selected book must remain without an attached cover; no images were removed automatically."
    end
    records = entries.reject { |entry| entry.fetch("work_key") == missing.fetch("work_key") || entry["cover_id"].nil? }.first(LIMIT).to_h do |entry|
      [ entry.fetch("work_key"), entry.except("work_key").merge("job_id" => nil, "status" => "planned") ]
    end
    { "limit" => LIMIT, "missing_case" => missing.slice("work_key", "book_id").merge(
      "reason" => missing["cover_id"] ? "preview_intentionally_omitted" : "source_cover_id_missing"
    ), "records" => records,
      "source_unavailable_work_keys" => entries.select { |entry| entry["cover_id"].nil? }.map { |entry| entry.fetch("work_key") } }
  end

  private

  def attached?(entry)
    @books.fetch(entry.fetch("work_key")).cover_image.attached?
  end
end
