class OpenLibraryClient
  BASE_URL = "https://openlibrary.org"
  def initialize
    @conn = Faraday.new(url: BASE_URL) do |f|
      f.options.timeout = 15
      f.options.open_timeout = 15
    end
  end
  def search(query)
    response = @conn.get("/search.json", { q: query })
    result = JSON.parse(response.body)
    result["docs"]
  rescue Faraday::Error => e
    Rails.logger.error("OpenLibraryClient#search failed: #{e.message}")
    []
  end
end
