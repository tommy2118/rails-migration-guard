# frozen_string_literal: true

require "rainbow"

module MigrationGuard
  # Handles colored output for the CLI
  module Colorizer
    class << self
      def colorize_output?
        return false if ENV["NO_COLOR"]
        return false unless MigrationGuard.configuration.colorize_output

        # Check if output is going to a TTY
        $stdout.tty?
      end

      def success(message)
        return message unless colorize_output?

        Rainbow(message).green
      end

      def warning(message)
        return message unless colorize_output?

        Rainbow(message).yellow
      end

      def error(message)
        return message unless colorize_output?

        Rainbow(message).red
      end

      def info(message)
        return message unless colorize_output?

        Rainbow(message).cyan
      end

      def bold(message)
        return message unless colorize_output?

        Rainbow(message).bright
      end

      # Specific formatting methods for migration output
      def format_checkmark
        success("✓")
      end

      def format_warning_symbol
        warning("⚠")
      end

      def format_error_symbol
        error("✗")
      end

      def format_migration_count(count, type)
        case type
        when :synced
          success("#{count} migrations")
        when :orphaned
          warning("#{count} migrations")
        when :missing
          error("#{count} migrations")
        else
          "#{count} migrations"
        end
      end

      def format_status_line(symbol, label, count, type)
        "#{symbol} #{label}: #{format_migration_count(count, type)}"
      end
    end
  end
end
