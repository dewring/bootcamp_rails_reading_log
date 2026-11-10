module DevelopmentLogFilter
  # Both development appenders use this predicate; true means keep the entry.
  def self.include_in_development_log?(log)
    return true if failure_entry?(log)
    return false if active_storage_entry?(log)
    return false if cache_hit_entry?(log)

    true
  end

  def self.failure_entry?(log)
    return true if log.level_index >= SemanticLogger::Levels.index(:warn)
    return true if log.exception

    # Controller completion and rescued-exception entries can use info severity.
    return false unless log.payload.is_a?(Hash)
    return true if log.payload[:status].to_i >= 400
    return true if log.payload[:exception] || log.payload[:exception_object]

    false
  end

  def self.active_storage_entry?(log)
    return true if log.name == "ActiveStorage" || log.name.start_with?("ActiveStorage::")

    # Active Storage SQL shares the application's Active Record logger.
    log.name == "ActiveRecord::Base" && log.message.to_s.start_with?("ActiveStorage::")
  end

  def self.cache_hit_entry?(log)
    # Keep cache misses useful for diagnosis without repeating successful reads.
    log.name == "Rails" && log.message.to_s.start_with?("Cache [HIT] for key: ")
  end

  private_class_method :failure_entry?, :active_storage_entry?, :cache_hit_entry?
end
