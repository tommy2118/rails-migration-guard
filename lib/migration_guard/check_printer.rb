# frozen_string_literal: true

require_relative "colorizer"

module MigrationGuard
  module CheckPrinter
    def print_check(name, status, details = nil)
      symbol = case status
               when :success then Colorizer.success("✓")
               when :warning then Colorizer.warning("⚠")
               when :error then Colorizer.error("✗")
               when :info then Colorizer.info("ℹ")
               end

      line = "#{symbol} #{name}"
      line += ": #{details}" if details
      puts line # rubocop:disable Rails/Output
    end
  end
end
