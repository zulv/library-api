module LogCapture
  def with_captured_logs
    capture = StringIO.new
    capture_logger = ActiveSupport::Logger.new(capture)
    original_level = Rails.logger.level
    Rails.logger.level = Logger::DEBUG
    Rails.logger.broadcast_to(capture_logger)
    yield
    capture.string
  ensure
    Rails.logger.stop_broadcasting_to(capture_logger)
    Rails.logger.level = original_level
  end
end

RSpec.configure do |config|
  config.include LogCapture
end
