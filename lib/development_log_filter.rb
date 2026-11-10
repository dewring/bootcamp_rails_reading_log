module DevelopmentLogFilter
  # Both development appenders use this predicate; true means keep the entry.
  def self.keep?(log)
    return true if log.level_index >= SemanticLogger::Levels.index(:warn)
    return true if log.exception
    return false if log.name == "ActiveStorage" || log.name.start_with?("ActiveStorage::")

    # Active Storage SQL shares the application's Active Record logger.
    return false if log.name == "ActiveRecord::Base" && log.message.to_s.start_with?("ActiveStorage::")

    true
  end
end
