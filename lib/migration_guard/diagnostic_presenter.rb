# frozen_string_literal: true

require_relative "colorizer"

module MigrationGuard
  # Formats diagnostic runner results for display
  class DiagnosticPresenter
    def initialize(colorizer: Colorizer, output: $stdout)
      @colorizer = colorizer
      @output = output
    end

    def print_header
      write @colorizer.bold("Running Migration Guard Diagnostics...")
      write
    end

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def print_summary(issues, warnings)
      write
      write @colorizer.bold("=" * 50)

      if issues.any?
        write @colorizer.error("Issues Found:")
        issues.each_with_index do |(title, description), index|
          write @colorizer.error("#{index + 1}. #{title}:")
          write "   #{description}"
          write
        end
      end

      if warnings.any?
        write @colorizer.warning("Warnings:")
        warnings.each_with_index do |(title, description), index|
          write @colorizer.warning("#{index + 1}. #{title}:")
          write "   #{description}"
          write
        end
      end

      print_overall_status(issues, warnings)
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    def print_overall_status(issues, warnings)
      status = if issues.any?
                 @colorizer.error("NEEDS ATTENTION (#{issues.size} issue(s))")
               elsif warnings.any?
                 @colorizer.warning("OK WITH WARNINGS (#{warnings.size} warning(s))")
               else
                 @colorizer.success("ALL SYSTEMS OK")
               end

      write @colorizer.bold("Overall Status: #{status}")
    end

    private

    def write(*args)
      @output.send(:puts, *args)
    end
  end
end
