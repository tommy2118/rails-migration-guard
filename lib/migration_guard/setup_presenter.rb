# frozen_string_literal: true

require_relative "colorizer"

module MigrationGuard
  # Formats setup assistant output for display
  class SetupPresenter
    def initialize(colorizer: Colorizer, output: $stdout)
      @colorizer = colorizer
      @output = output
    end

    def print_welcome_header
      write @colorizer.bold("=" * 60)
      write @colorizer.bold("\u{1F680} Welcome to Rails Migration Guard Setup!")
      write @colorizer.bold("=" * 60)
      write ""
      write "This assistant will help you set up your development environment"
      write "and ensure your migration state matches the team's configuration."
      write ""
    end

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def print_summary(issues)
      write ""
      write @colorizer.bold("\u{1F4CB} Summary")
      write "=" * 20

      if issues.empty?
        write @colorizer.success("\u{2705} Everything looks good! Your environment is properly set up.")
        write ""
        write "You can start developing with confidence. Migration Guard will help you:"
        write "\u{2022} Track migrations across branches"
        write "\u{2022} Detect orphaned migrations"
        write "\u{2022} Coordinate with your team"
      else
        write @colorizer.warning("\u{26A0}\u{FE0F}  #{issues.size} issue(s) found that need attention:")
        write ""

        issues.each_with_index do |(title, description), index|
          write @colorizer.warning("#{index + 1}. #{title}")
          write "   #{description}"
          write ""
        end
      end
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    def offer_interactive_fixes(suggestions)
      return if suggestions.empty?

      write @colorizer.bold("\u{1F6E0}\u{FE0F}  Recommended Actions")
      write "=" * 25

      suggestions.each_with_index do |(_action, description), index|
        write @colorizer.info("#{index + 1}. #{description}")
      end

      write ""
      @output.send(:print, "Would you like me to run these commands for you? (y/N): ")
      response = $stdin.gets.chomp.downcase

      %w[y yes].include?(response)
    end

    def print_helpful_commands
      write ""
      write @colorizer.bold("\u{1F4DA} Helpful Commands")
      write "=" * 20
      write "\u{2022} rails db:migration:status     - Check migration status"
      write "\u{2022} rails db:migration:doctor     - Run diagnostics"
      write "\u{2022} rails db:migration:history    - View migration history"
      write "\u{2022} rails db:migration:authors    - See team contributions"
      write ""
      write @colorizer.success("\u{1F389} Happy coding!")
    end

    private

    def write(*args)
      @output.send(:puts, *args)
    end
  end
end
