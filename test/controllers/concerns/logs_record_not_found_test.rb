require "test_helper"

class LogsRecordNotFoundTest < ActiveSupport::TestCase
  test "not_found still returns the original controller's result" do
    dummy_class = build_dummy_class(build_fake_logger)

    result = dummy_class.new.not_found

    assert_equal :original_result, result
  end

  test "not_found logs the event via measure_info" do
    fake_logger = build_fake_logger
    dummy_class = build_dummy_class(fake_logger)

    dummy_class.new.not_found

    assert fake_logger.info_logged
  end

  private

  def build_fake_logger
    Class.new do
      attr_reader :info_logged

      def initialize
        @info_logged = false
      end

      def measure_info(_event, payload:)
        @info_logged = true
        yield
      end
    end.new
  end

  def build_dummy_class(fake_logger)
    Class.new do
      define_method(:params) { { id: 1 } }
      define_method(:logger) { fake_logger }

      def not_found
        :original_result
      end

      prepend LogsRecordNotFound
    end
  end
end
