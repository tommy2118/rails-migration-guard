# frozen_string_literal: true

require "logger"

module MigrationGuard
  module Logger
    class << self
      def logger
        @logger ||= MigrationGuard.configuration.logger ||
                    (defined?(Rails) && Rails.logger) ||
                    ::Logger.new($stdout)
      end

      def visible_logger
        @visible_logger ||= ::Logger.new($stdout).tap do |logger|
          logger.level = ::Logger::DEBUG
          logger.formatter = proc do |severity, datetime, progname, msg|
            "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity} MigrationGuard -- #{msg}\n"
          end
        end
      end

      def file_logger(path = "log/migration_guard.log")
        ::Logger.new(path).tap do |logger|
          logger.level = ::Logger::DEBUG
          logger.formatter = proc do |severity, datetime, progname, msg|
            "[#{datetime.strftime('%Y-%m-%d %H:%M:%S.%L')}] #{severity} MigrationGuard -- #{msg}\n"
          end
        end
      end

      def debug(message, context = {})
        return unless debug?

        log(:debug, message, context)
      end

      def info(message, context = {})
        return unless info?

        log(:info, message, context)
      end

      def warn(message, context = {})
        return unless warn?

        log(:warn, message, context)
      end

      def error(message, context = {})
        return unless error?

        log(:error, message, context)
      end

      def fatal(message, context = {})
        log(:fatal, message, context)
      end

      private

      def log(level, message, context)
        formatted_message = format_message(message, context)
        logger.send(level, formatted_message)
        
        # Also output to visible logger if enabled and in debug mode
        if MigrationGuard.configuration.visible_debug && level == :debug
          visible_logger.debug(format_visible_message(message, context))
        end
      end

      def format_message(message, context)
        return message if context.empty?

        "[#{timestamp}] #{log_level_name} MigrationGuard -- #{message} #{format_context(context)}"
      end

      def format_visible_message(message, context)
        return message if context.empty?

        "#{message} #{format_context(context)}"
      end

      def format_context(context)
        return "" if context.empty?

        "-- #{context.map { |k, v| "#{k}: #{v}" }.join(', ')}"
      end

      def timestamp
        Time.current.strftime("%Y-%m-%d %H:%M:%S.%L")
      end

      def log_level_name
        MigrationGuard.configuration.log_level.to_s.upcase
      end

      def debug?
        log_level_value <= ::Logger::DEBUG
      end

      def info?
        log_level_value <= ::Logger::INFO
      end

      def warn?
        log_level_value <= ::Logger::WARN
      end

      def error?
        log_level_value <= ::Logger::ERROR
      end

      def log_level_value
        case MigrationGuard.configuration.log_level
        when :debug then ::Logger::DEBUG
        when :info then ::Logger::INFO
        when :warn then ::Logger::WARN
        when :error then ::Logger::ERROR
        when :fatal then ::Logger::FATAL
        end
      end
    end
  end
end
