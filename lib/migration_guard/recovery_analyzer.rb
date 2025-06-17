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

    def analyze
      @inconsistencies = []

      @checkers.each do |checker|
        @inconsistencies.concat(checker.check)
      rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::StatementInvalid => e
        Rails.logger&.error "Database error during recovery analysis: #{e.message}"
        # Continue with other checkers
      end

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
