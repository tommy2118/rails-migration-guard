# frozen_string_literal: true

module MigrationGuard
  # Centralized helper for determining interactive mode across the gem
  module InteractiveMode
    class << self
      # Determines if we should run in interactive mode based on:
      # 1. Explicit interactive parameter (if false, always non-interactive)
      # 2. Environment variable overrides (FORCE, NON_INTERACTIVE, AUTO)
      # 3. TTY availability (if auto_detect_tty is enabled)
      #
      # @param requested_interactive [Boolean] whether interactive mode was requested
      # @return [Boolean] true if we should run interactively
      def interactive?(requested_interactive: true)
        return false unless requested_interactive
        return false if forced_non_interactive?

        # Respect configuration for TTY auto-detection
        return true unless MigrationGuard.configuration.auto_detect_tty

        $stdin.tty?
      end

      # Check if any environment variables force non-interactive mode
      def forced_non_interactive?
        ENV["FORCE"] == "true" || ENV["NON_INTERACTIVE"] == "true" || ENV["AUTO"] == "true"
      end

      # Log when we auto-detect non-TTY and switch modes
      def log_tty_detection(requested_interactive, actual_interactive, logger_method)
        return unless requested_interactive && !actual_interactive && !forced_non_interactive?

        message = "Non-TTY environment detected, running in non-interactive mode"

        # Use the appropriate logger based on context
        if logger_method == :rails_logger
          Rails.logger&.info "[MigrationGuard] #{message}"
        else
          MigrationGuard::Logger.info(message)
        end
      end
    end
  end
end
