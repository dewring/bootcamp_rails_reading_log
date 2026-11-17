module ReadingScenarioEnvironment
  def self.enabled?
    Rails.env.development? || (Rails.env.production? && ENV["ALLOW_PRODUCTION_SCENARIO"] == "true")
  end
end
