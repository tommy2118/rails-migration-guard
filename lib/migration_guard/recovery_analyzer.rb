# frozen_string_literal: true

require "migration_guard/colorizer"
require "migration_guard/recovery/issue_formatter"
require "migration_guard/recovery/issue_checker"
require "migration_guard/recovery/rollback_checker"
require "migration_guard/recovery/schema_checker"
require "migration_guard/recovery/file_checker"
require "migration_guard/recovery/version_conflict_checker"

module MigrationGuard
  # RecoveryAnalyzer detects inconsistent migration states that may need recovery
  class RecoveryAnalyzer
    attr_reader :inconsistencies

    def initialize
      @inconsistencies = []
      @checkers = initialize_checkers
    end

    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    def analyze
      @inconsistencies = []
      database_available = true

      @checkers.each do |checker|
        @inconsistencies.concat(checker.check)
      rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::NoDatabaseError => e
        unless database_available
          # Only warn once about database connection issues
          database_available = false
          Rails.logger&.error "Database connection error: #{e.message}"
          Rails.logger&.warn "Continuing analysis with limited functionality..."
        end
        # Continue with other checkers
      rescue ActiveRecord::StatementInvalid, ActiveRecord::QueryAborted => e
        Rails.logger&.error "Database query error during #{checker.class.name}: #{e.message}"
        # Continue with other checkers
      rescue StandardError => e
        # Catch any other database-related errors
        Rails.logger&.error "Unexpected error during #{checker.class.name}: #{e.class} - #{e.message}"
        Rails.logger&.debug { e.backtrace.join("\n") }
        # Continue with other checkers to gather as much info as possible
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

      @inconsistencies
    end

    def issues?
      @inconsistencies.any?
    end

    def format_analysis_report
      return no_issues_message if @inconsistencies.empty?

      build_report
    end

    private

    def initialize_checkers
      [
        Recovery::RollbackChecker.new,
        Recovery::SchemaChecker.new,
        Recovery::FileChecker.new,
        Recovery::VersionConflictChecker.new
      ]
    end

    def no_issues_message
      Colorizer.success("No migration inconsistencies detected.")
    end

    def build_report
      lines = []
      lines << Colorizer.error("⚠️  Detected migration inconsistencies:")
      lines << ""
      lines.concat(format_issues)
      lines << ""
      lines << Colorizer.warning("Run 'rails db:migration:recover' to resolve these issues.")
      lines.join("\n")
    end

    def format_issues
      @inconsistencies.map.with_index do |issue, index|
        Recovery::IssueFormatter.format(issue, index + 1)
      end
    end
  end
end
