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
  def fetch_work(ol_work_key)
    response = @conn.get("/works/#{ol_work_key}.json")
    result = JSON.parse(response.body)
    result
  rescue Faraday::Error => e
    Rails.logger.error("OpenLibraryClient#fetch_work failed: #{e.message}")
    nil
  end
  def fetch_editions(ol_work_key)
    response = @conn.get("/works/#{ol_work_key}/editions.json")
    result = JSON.parse(response.body)
    result
  rescue Faraday::Error => e
    Rails.logger.error("OpenLibraryClient#fetch_editions failed: #{e.message}")
    nil
  end
end
