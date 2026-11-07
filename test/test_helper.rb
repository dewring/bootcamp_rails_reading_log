ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "bcrypt"
require "webmock/minitest"
require "minitest/mock"
require "rspec/mocks/minitest_integration"

class ActiveSupport::TestCase
  require "turbo/broadcastable/test_helper"
  include Turbo::Broadcastable::TestHelper
  parallelize(workers: :number_of_processors)
  fixtures :all

  teardown do
    # Committed tests reload fixtures next time; truncate this worker's tables without model callbacks.
    if !use_transactional_tests || self.class.uses_transaction?(name)
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        connection.truncate_tables(*connection.tables)
      end
    end
  end
  Rack::Attack.enabled = false
  Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
end
