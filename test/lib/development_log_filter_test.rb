require_relative "../../config/boot"
require "minitest/autorun"
require "semantic_logger"
require "stringio"
require_relative "../../lib/development_log_filter"

class DevelopmentLogFilterTest < Minitest::Test
  def setup
    @output = StringIO.new
    @appender = SemanticLogger::Appender::IO.new(
      @output,
      level: :trace,
      formatter: :json,
      filter: DevelopmentLogFilter.method(:keep?)
    )
  end

  def test_routine_storage_operations_and_controller_messages_are_hidden
    [ "ActiveStorage", "ActiveStorage::Blobs::RedirectController", "ActiveStorage::AnalyzeJob" ].each do |name|
      [ :trace, :debug, :info ].each do |level|
        refute @appender.should_log?(log_entry(name, level, "Downloaded file"))
      end
    end
  end

  def test_active_storage_queries_are_hidden_including_cached_queries
    [ "ActiveStorage::Attachment Load", "ActiveStorage::Blob Load", "ActiveStorage::VariantRecord Load" ].each do |message|
      log = log_entry("ActiveRecord::Base", :debug, message)
      log.payload = { sql: "SELECT ...", cached: true }

      refute @appender.should_log?(log)
    end
  end

  def test_application_queries_and_requests_remain_visible
    [ [ "ActiveRecord::Base", :debug, "Book Load" ],
      [ "BooksController", :info, "Completed" ],
      [ "Rails", :info, "ActiveStorage::Blob was referenced by application code" ] ].each do |name, level, message|
      log = log_entry(name, level, message)

      assert @appender.should_log?(log)
      @appender.log(log)
      assert_includes @output.string, message
    end
  end

  def test_storage_warnings_errors_and_fatal_messages_remain_visible
    [ "ActiveStorage", "ActiveStorage::AnalyzeJob", "ActiveRecord::Base" ].each do |name|
      [ :warn, :error, :fatal ].each do |level|
        assert @appender.should_log?(log_entry(name, level, "ActiveStorage::Blob failed"))
      end
    end
  end

  def test_storage_entries_with_exceptions_remain_visible_even_at_info_level
    log = log_entry("ActiveStorage", :info, "Download failed")
    log.exception = IOError.new("Storage unavailable")

    assert @appender.should_log?(log)
  end

  def test_entries_without_a_message_remain_visible
    assert @appender.should_log?(log_entry("ActiveRecord::Base", :debug, nil))
  end

  private

  def log_entry(name, level, message)
    log = SemanticLogger::Log.new(name, level)
    log.message = message
    log
  end
end
