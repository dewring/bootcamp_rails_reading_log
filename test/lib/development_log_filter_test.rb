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
      filter: DevelopmentLogFilter.method(:include_in_development_log?)
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

  def test_successful_cache_reads_are_hidden_but_cache_misses_remain_visible
    refute @appender.should_log?(log_entry("Rails", :info, "Cache [HIT] for key: book:180:editions:list"))
    assert @appender.should_log?(log_entry("Rails", :info, "Cache [MISS] for key: book:180:editions:list"))
  end

  def test_cache_hit_warnings_and_exceptions_remain_visible
    message = "Cache [HIT] for key: book:180:editions:list"
    assert @appender.should_log?(log_entry("Rails", :warn, message))

    log = log_entry("Rails", :info, message)
    log.exception = IOError.new("Cache unavailable")

    assert @appender.should_log?(log)
  end

  def test_other_loggers_can_report_cache_hits
    assert @appender.should_log?(log_entry("BookProgressJob", :info, "Cache [HIT] for key: progress"))
  end

  def test_failed_storage_responses_remain_visible_at_info_level
    [ 400, 404, 422, 500 ].each do |status|
      log = log_entry("ActiveStorage::Blobs::RedirectController", :info, "Completed")
      log.payload = { status: status }

      assert @appender.should_log?(log)
    end
  end

  def test_successful_storage_responses_and_redirects_remain_hidden
    [ 200, 302 ].each do |status|
      log = log_entry("ActiveStorage::Blobs::RedirectController", :info, "Completed")
      log.payload = { status: status }

      refute @appender.should_log?(log)
    end
  end

  def test_storage_exceptions_in_structured_payloads_remain_visible
    [ { exception: "ActiveStorage::FileNotFoundError" }, { exception_object: IOError.new("File missing") } ].each do |payload|
      log = log_entry("ActiveStorage::Blobs::RedirectController", :info, "rescue_from handled exception")
      log.payload = payload

      assert @appender.should_log?(log)
    end
  end

  private

  def log_entry(name, level, message)
    log = SemanticLogger::Log.new(name, level)
    log.message = message
    log
  end
end
