class OpenLibraryClient
  include SemanticLogger::Loggable
  BASE_URL = "https://openlibrary.org"

  def initialize
    @conn = Faraday.new(url: BASE_URL) do |f|
      f.options.timeout = 15
      f.options.open_timeout = 15
    end
  end
  def search(query, page: 1, limit: 10)
    logger.measure_info(
      "Searching in Open Library",
      payload: { event: "open_library.search", query: query, status: "success" }
    ) do
      response = @conn.get("/search.json", { q: query, page: page, limit: limit })
      result = JSON.parse(response.body)
      { docs: result["docs"] || [], total: result["numFound"] || 0 }
    rescue Faraday::Error => e
      Rails.logger.error(
        "Searching in Open Library",
        event: "open_library.search", query: query, status: "error",
        exception_class: e.class.name, error: e.message
      )
      { docs: [], total: 0 }
    end
  end

  def fetch_work(ol_work_key)
    logger.measure_info(
      "Fetching work from Open Library",
      payload: { event: "open_library.fetch_work", ol_work_key: ol_work_key, status: "success" }
    ) do
      response = @conn.get("/works/#{ol_work_key}.json")
      JSON.parse(response.body)

      rescue Faraday::TimeoutError => e
        Rails.logger.error(
          "Fetching work from Open Library",
          event: "open_library.fetch_work", ol_work_key: ol_work_key, status: "timeout",
          exception_class: e.class.name, error: e.message
        )
        nil
      rescue Faraday::Error => e
        Rails.logger.error(
          "Fetching work from Open Library",
          event: "open_library.fetch_work", ol_work_key: ol_work_key, status: "error",
          exception_class: e.class.name, error: e.message
        )
        nil
    end
  end

  def fetch_editions(ol_work_key)
    logger.measure_info(
      "Fetching edition from Open Library",
      payload: { event: "open_library.fetch_edition", ol_work_key: ol_work_key, status: "success" }
    ) do
      response = @conn.get("/works/#{ol_work_key}/editions.json")
      JSON.parse(response.body)

      rescue Faraday::TimeoutError => e
        Rails.logger.error(
          "Fetching edition from Open Library",
          event: "open_library.fetch_edition", ol_work_key: ol_work_key, status: "timeout",
          exception_class: e.class.name, error: e.message
        )
        nil
      rescue Faraday::Error => e
        Rails.logger.error(
          "Fetching edition from Open Library",
          event: "open_library.fetch_edition", ol_work_key: ol_work_key, status: "error",
          exception_class: e.class.name, error: e.message
        )
        nil
    end
  end
end
