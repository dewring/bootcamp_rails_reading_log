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

  def fetch_by_isbn(isbn)
    logger.measure_info(
      "Fetching edition by ISBN from Open Library",
      payload: { event: "open_library.fetch_by_isbn", isbn: isbn, status: "success" }
    ) do
      # Open Library's /isbn/{isbn}.json redirects (302) to the canonical
      # /books/{ol_edition_key}.json rather than returning the body directly.
      response = @conn.get("/isbn/#{isbn}.json")
      if (300..399).cover?(response.status) && response.headers["location"]
        response = @conn.get(response.headers["location"])
      end
      next nil unless response.status == 200
      JSON.parse(response.body)

      rescue Faraday::TimeoutError => e
        Rails.logger.error(
          "Fetching edition by ISBN from Open Library",
          event: "open_library.fetch_by_isbn", isbn: isbn, status: "timeout",
          exception_class: e.class.name, error: e.message
        )
        nil
      rescue Faraday::Error => e
        Rails.logger.error(
          "Fetching edition by ISBN from Open Library",
          event: "open_library.fetch_by_isbn", isbn: isbn, status: "error",
          exception_class: e.class.name, error: e.message
        )
        nil
    end
  end

  def fetch_author(ol_author_key)
    logger.measure_info(
      "Fetching author from Open Library",
      payload: { event: "open_library.fetch_author", ol_author_key: ol_author_key, status: "success" }
    ) do
      response = @conn.get("/authors/#{ol_author_key}.json")
      JSON.parse(response.body)

      rescue Faraday::TimeoutError => e
        Rails.logger.error(
          "Fetching author from Open Library",
          event: "open_library.fetch_author", ol_author_key: ol_author_key, status: "timeout",
          exception_class: e.class.name, error: e.message
        )
        nil
      rescue Faraday::Error => e
        Rails.logger.error(
          "Fetching author from Open Library",
          event: "open_library.fetch_author", ol_author_key: ol_author_key, status: "error",
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
      # /works/{key}/editions.json is paginated (50 per page). Prolific
      # works (e.g. Dune has 160 editions) need every page followed via
      # "links.next", or editions past the first 50 are silently missed.
      entries = []
      path = "/works/#{ol_work_key}/editions.json"

      10.times do
        response = @conn.get(path)
        page = JSON.parse(response.body)
        entries.concat(page["entries"] || [])
        path = page.dig("links", "next")
        break if path.blank?
      end

      { "entries" => entries }

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
