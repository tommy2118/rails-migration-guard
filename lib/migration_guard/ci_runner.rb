# frozen_string_literal: true

# rubocop:disable Rails/Output
module MigrationGuard
  # Handles CI/CD integration for automated environments
  # rubocop:disable Metrics/ClassLength
  class CiRunner
    VALID_FORMATS = %w[text json].freeze
    VALID_STRICTNESS_LEVELS = %w[strict warning permissive].freeze

    # Exit codes for CI environments
    EXIT_SUCCESS = 0
    EXIT_WARNING = 1
    EXIT_ERROR = 2

    def initialize(format: "text", strict: false, strictness: nil)
      @format = normalize_format(format)
      @strictness = normalize_strictness(strict, strictness)
      @reporter = Reporter.new
      @git_integration = GitIntegration.new
    end

    def run
      unless MigrationGuard.enabled?
        output_disabled_message
        return EXIT_SUCCESS
      end

      result = analyze_migrations
      output_result(result)
      determine_exit_code(result)
    rescue StandardError => e
      output_error(e)
      EXIT_ERROR
    end

    private

    def analyze_migrations
      orphaned = @reporter.orphaned_migrations
      missing = @reporter.missing_migrations

      {
        status: determine_status(orphaned, missing),
        orphaned_migrations: format_migrations(orphaned),
        missing_migrations: format_migrations(missing),
        summary: build_summary(orphaned, missing),
        branch_info: build_branch_info,
        timestamp: Time.current.iso8601
      }
    end

    def determine_status(orphaned, missing)
      return "error" if orphaned.any? && @strictness == "strict"
      return "error" if missing.any? && @strictness == "strict"
      return "warning" if orphaned.any? || missing.any?

      "success"
    end

    # rubocop:disable Metrics/MethodLength
    def format_migrations(migrations)
      # Handle both migration record objects and version strings
      migrations.map do |migration|
        if migration.respond_to?(:version)
          # Migration record object
          {
            version: migration.version,
            file: "#{migration.version}_*.rb",
            branch: migration.branch,
            author: migration.author,
            created_at: migration.created_at&.iso8601
          }
        else
          # Version string (for missing migrations)
          {
            version: migration,
            file: "#{migration}_*.rb",
            branch: @git_integration.main_branch,
            author: "unknown",
            created_at: nil
          }
        end
      end
    end
    # rubocop:enable Metrics/MethodLength

    def build_summary(orphaned, missing)
      {
        total_orphaned: orphaned.size,
        total_missing: missing.size,
        issues_found: orphaned.size + missing.size,
        main_branch: @git_integration.main_branch,
        current_branch: @git_integration.current_branch
      }
    end

    def build_branch_info
      {
        current: @git_integration.current_branch,
        main: @git_integration.main_branch,
        ahead_count: calculate_ahead_count,
        behind_count: calculate_behind_count
      }
    rescue StandardError
      {
        current: "unknown",
        main: "unknown",
        ahead_count: 0,
        behind_count: 0
      }
    end

    def calculate_ahead_count
      # Simplified implementation - could be enhanced with actual git comparison
      0
    end

    def calculate_behind_count
      # Simplified implementation - could be enhanced with actual git comparison
      0
    end

    def output_result(result)
      case @format
      when "json"
        output_json(result)
      else
        output_text(result)
      end
    end

    def output_json(result)
      json_output = {
        migration_guard: {
          version: MigrationGuard::VERSION,
          status: result[:status],
          summary: result[:summary],
          orphaned_migrations: result[:orphaned_migrations],
          missing_migrations: result[:missing_migrations],
          branch_info: result[:branch_info],
          timestamp: result[:timestamp],
          exit_code: determine_exit_code(result),
          strictness: @strictness
        }
      }

      puts JSON.pretty_generate(json_output)
    end

    def output_text(result)
      puts format_text_header(result)
      puts ""

      if result[:summary][:issues_found].positive?
        output_text_issues(result)
      else
        puts "✅ No migration issues found"
      end

      puts ""
      output_text_summary(result)
    end

    def format_text_header(result)
      status_emoji = case result[:status]
                     when "success" then "✅"
                     when "warning" then "⚠️ "
                     when "error" then "❌"
                     end

      branch_info = result[:branch_info]
      "#{status_emoji} Migration Guard CI Check (#{branch_info[:current]} → #{branch_info[:main]})"
    end

    # rubocop:disable Metrics/AbcSize
    def output_text_issues(result)
      if result[:orphaned_migrations].any?
        puts "🔍 Orphaned Migrations Found:"
        result[:orphaned_migrations].each do |migration|
          puts "  • #{migration[:version]} (#{migration[:branch]}) - #{migration[:author]}"
        end
        puts ""
      end

      if result[:missing_migrations].any?
        puts "📥 Missing Migrations:"
        result[:missing_migrations].each do |migration|
          puts "  • #{migration[:version]} (exists in #{result[:branch_info][:main]})"
        end
        puts ""
      end

      output_text_recommendations(result)
    end
    # rubocop:enable Metrics/AbcSize

    # rubocop:disable Metrics/AbcSize
    def output_text_recommendations(result)
      puts "💡 Recommended Actions:"

      if result[:orphaned_migrations].any?
        puts "  1. Roll back orphaned migrations:"
        result[:orphaned_migrations].each do |migration|
          puts "     rails db:migration:rollback_specific VERSION=#{migration[:version]}"
        end
        puts "  2. Or commit migration files if they should be included"
      end

      return unless result[:missing_migrations].any?

      puts "  1. Pull latest changes from #{result[:branch_info][:main]}:"
      puts "     git pull origin #{result[:branch_info][:main]}"
      puts "  2. Run migrations:"
      puts "     rails db:migrate"
    end
    # rubocop:enable Metrics/AbcSize

    def output_text_summary(result)
      summary = result[:summary]
      puts "📊 Summary:"
      puts "   Orphaned: #{summary[:total_orphaned]}"
      puts "   Missing: #{summary[:total_missing]}"
      puts "   Strictness: #{@strictness}"
      puts "   Exit code: #{determine_exit_code(result)}"
    end

    def determine_exit_code(result)
      case result[:status]
      when "success"
        EXIT_SUCCESS
      when "warning"
        @strictness == "strict" ? EXIT_ERROR : EXIT_WARNING
      when "error"
        EXIT_ERROR
      else
        EXIT_ERROR
      end
    end

    def output_disabled_message
      message = {
        status: "disabled",
        message: "MigrationGuard is not enabled in #{Rails.env} environment",
        exit_code: EXIT_SUCCESS
      }

      case @format
      when "json"
        puts JSON.pretty_generate(migration_guard: message)
      else
        puts "ℹ️  MigrationGuard is not enabled in #{Rails.env} environment"
      end
    end

    def output_error(error)
      error_info = {
        status: "error",
        error: error.message,
        backtrace: error.backtrace&.first(5),
        exit_code: EXIT_ERROR
      }

      case @format
      when "json"
        puts JSON.pretty_generate(migration_guard: error_info)
      else
        puts "❌ Error running Migration Guard CI check:"
        puts "   #{error.message}"
        puts ""
        puts "For debugging, run with more verbose logging or check your configuration."
      end
    end

    def normalize_format(format)
      format = format.to_s.downcase
      VALID_FORMATS.include?(format) ? format : "text"
    end

    def normalize_strictness(strict, strictness_level)
      # Handle legacy --strict flag
      return "strict" if strict

      # Handle new --strictness option
      strictness_level = strictness_level.to_s.downcase if strictness_level
      VALID_STRICTNESS_LEVELS.include?(strictness_level) ? strictness_level : "warning"
    end
  end
  # rubocop:enable Metrics/ClassLength
end
# rubocop:enable Rails/Output
