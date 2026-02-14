# frozen_string_literal: true

require_relative "ci_presenter"

module MigrationGuard
  # Handles CI/CD integration for automated environments
  class CiRunner
    VALID_FORMATS = %w[text json].freeze
    VALID_STRICTNESS_LEVELS = %w[strict warning permissive].freeze

    # Exit codes for CI environments
    EXIT_SUCCESS = 0
    EXIT_WARNING = 1
    EXIT_ERROR = 2

    def initialize(format: "text", strict: false, strictness: nil,
                   reporter: Reporter.new, git_integration: GitIntegration.new)
      @format = normalize_format(format)
      @strictness = normalize_strictness(strict, strictness)
      @reporter = reporter
      @git_integration = git_integration
      @presenter = CiPresenter.new
    end

    def run
      unless MigrationGuard.enabled?
        @presenter.output_disabled_message(@format)
        return EXIT_SUCCESS
      end

      result = analyze_migrations
      @presenter.output_result(result, @format, @strictness)
      determine_exit_code(result)
    rescue StandardError => e
      @presenter.output_error(e, @format)
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
      migrations.map do |migration|
        if migration.respond_to?(:version)
          {
            version: migration.version,
            file: "#{migration.version}_*.rb",
            branch: migration.branch,
            author: migration.author,
            created_at: migration.created_at&.iso8601
          }
        else
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
      0
    end

    def calculate_behind_count
      0
    end

    def determine_exit_code(result)
      case result[:status]
      when "success"
        EXIT_SUCCESS
      when "warning"
        @strictness == "strict" ? EXIT_ERROR : EXIT_WARNING
      else # "error" or any other status
        EXIT_ERROR
      end
    end

    def normalize_format(format)
      format = format.to_s.downcase
      VALID_FORMATS.include?(format) ? format : "text"
    end

    def normalize_strictness(strict, strictness_level)
      return "strict" if strict

      strictness_level = strictness_level.to_s.downcase if strictness_level
      VALID_STRICTNESS_LEVELS.include?(strictness_level) ? strictness_level : "warning"
    end
  end
end
