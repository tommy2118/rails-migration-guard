# frozen_string_literal: true

module MigrationGuard
  # Shared time formatting utilities
  module TimeFormatters
    module_function

    # Formats a duration in seconds to a human-readable string
    # @param seconds [Numeric] the duration in seconds
    # @return [String] formatted duration (e.g., "5m", "2h", "3d")
    def format_duration(seconds)
      return "0m" if seconds <= 0

      minutes = (seconds / 60.0).round

      if minutes < 60
        "#{minutes}m"
      elsif minutes < 1440 # Less than 24 hours
        hours = minutes / 60
        "#{hours}h"
      else
        days = minutes / 1440
        "#{days}d"
      end
    end

    # Formats the time elapsed since a given timestamp
    # @param timestamp [Time] the starting time
    # @return [String] formatted duration since the timestamp
    def format_time_since(timestamp)
      return nil unless timestamp

      seconds = Time.current - timestamp
      format_duration(seconds)
    end
  end
end
