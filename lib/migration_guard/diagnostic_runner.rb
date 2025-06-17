# frozen_string_literal: true

require_relative "colorizer"

module MigrationGuard
  # Comprehensive diagnostic runner for troubleshooting MigrationGuard issues
  # rubocop:disable Metrics/ClassLength
  class DiagnosticRunner
    def initialize
      @issues = []
      @warnings = []
      @colorizer = Colorizer
    end

    def run_all_checks
      print_header

      check_database_connection
      check_migration_guard_tables
      check_git_repository
      check_git_branch_detection
      check_target_branch_configuration
      check_orphaned_migrations
      check_missing_migrations
      check_schema_consistency
      check_environment_configuration

      print_summary
    end

    private

    attr_reader :issues, :warnings, :colorizer

    def print_header
      puts colorizer.bold("Running Migration Guard Diagnostics...") # rubocop:disable Rails/Output
      puts # rubocop:disable Rails/Output
    end

    def check_database_connection
      ActiveRecord::Base.connection.execute("SELECT 1")
      print_check("Database connection", :success)
    rescue StandardError => e
      add_issue("Database connection failed", "Check your database configuration: #{e.message}")
      print_check("Database connection", :error)
    end

    def check_migration_guard_tables
      MigrationGuard::MigrationGuardRecord.table_exists?
      count = MigrationGuard::MigrationGuardRecord.count
      print_check("Migration guard tables", :success, "#{count} records")
    rescue StandardError
      add_issue("Migration guard tables missing", "Run 'rails generate migration_guard:install' and 'rails db:migrate'")
      print_check("Migration guard tables", :error)
    end

    def check_git_repository
      git_integration = GitIntegration.new
      current_branch = git_integration.current_branch
      print_check("Git repository", :success, "current: #{current_branch}")
    rescue GitError => e
      add_issue("Git repository not found or not configured", e.message)
      print_check("Git repository", :error)
    rescue StandardError => e
      add_issue("Git integration failed", e.message)
      print_check("Git repository", :error)
    end

    def check_git_branch_detection
      git_integration = GitIntegration.new
      main_branch = git_integration.main_branch
      print_check("Git branch detection", :success, "main: #{main_branch}")
    rescue GitError, StandardError => e
      add_issue("Git branch detection failed", e.message)
      print_check("Git branch detection", :error)
    end

    def check_target_branch_configuration
      config = MigrationGuard.configuration
      if config.target_branches&.any?
        branches = config.target_branches.join(", ")
        print_check("Target branch configuration", :success, "configured: #{branches}")
      else
        add_warning("No target branches configured",
                    "Consider setting config.target_branches for multi-branch workflows")
        print_check("Target branch configuration", :warning, "using default")
      end
    end

    def check_orphaned_migrations
      reporter = Reporter.new
      orphaned = reporter.orphaned_migrations

      if orphaned.empty?
        print_check("Orphaned migrations", :success, "none found")
      else
        count = orphaned.size
        age_info = orphaned.map { |m| days_old(m.created_at) }.max
        add_issue("Orphaned migrations detected",
                  "Run 'rails db:migration:rollback_orphaned' to clean up #{count} migration(s)")
        print_check("Orphaned migrations", :error, "#{count} found (oldest: #{age_info} days)")
      end
    rescue StandardError => e
      add_issue("Failed to check orphaned migrations", e.message)
      print_check("Orphaned migrations", :error)
    end

    def check_missing_migrations
      reporter = Reporter.new
      missing_report = reporter.missing_migrations

      if missing_report.empty?
        print_check("Missing migrations", :success, "none found")
      else
        total_missing = missing_report.values.sum(&:size)
        branches = missing_report.keys.join(", ")
        add_warning("Missing migrations from trunk", "Consider running 'rails db:migrate' or merging from #{branches}")
        print_check("Missing migrations", :warning, "#{total_missing} found in: #{branches}")
      end
    rescue StandardError => e
      add_issue("Failed to check missing migrations", e.message)
      print_check("Missing migrations", :error)
    end

    def check_schema_consistency
      issues = analyze_schema_consistency

      if issues.empty?
        print_check("Schema consistency", :success, "schema_migrations in sync")
      else
        report_schema_issues(issues)
      end
    rescue StandardError => e
      add_issue("Schema consistency check failed", e.message)
      print_check("Schema consistency", :error)
    end

    def analyze_schema_consistency
      schema_versions = fetch_schema_migrations
      tracked_versions = MigrationGuard::MigrationGuardRecord.pluck(:version)

      {
        missing_from_schema: find_missing_from_schema(schema_versions),
        rolled_back_in_schema: find_rolled_back_in_schema(schema_versions),
        untracked_in_schema: schema_versions - tracked_versions
      }.reject { |_, v| v.empty? }
    end

    def find_missing_from_schema(schema_versions)
      MigrationGuard::MigrationGuardRecord.applied
                                          .reject { |r| schema_versions.include?(r.version) }
    end

    def find_rolled_back_in_schema(schema_versions)
      MigrationGuard::MigrationGuardRecord.rolled_back
                                          .select { |r| schema_versions.include?(r.version) }
    end

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def report_schema_issues(issues)
      summary_parts = []

      if issues[:missing_from_schema]
        count = issues[:missing_from_schema].size
        summary_parts << "#{count} tracked as applied but missing from schema"
        versions = issues[:missing_from_schema].map(&:version).join(", ")
        add_issue("Schema inconsistency detected",
                  "Migrations tracked as 'applied' but missing from schema_migrations: #{versions}")
      end

      if issues[:rolled_back_in_schema]
        count = issues[:rolled_back_in_schema].size
        summary_parts << "#{count} rolled back but still in schema"
        versions = issues[:rolled_back_in_schema].map(&:version).join(", ")
        add_issue("Rolled back migrations in schema",
                  "Migrations tracked as 'rolled_back' but still in schema_migrations: #{versions}")
      end

      if issues[:untracked_in_schema]
        count = issues[:untracked_in_schema].size
        summary_parts << "#{count} in schema but not tracked"
        versions = issues[:untracked_in_schema].join(", ")
        add_warning("Untracked migrations in schema",
                    "Migrations in schema_migrations but not tracked: #{versions}")
      end

      print_check("Schema consistency", :error, summary_parts.join(", "))
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    def fetch_schema_migrations
      ActiveRecord::Base.connection.select_values("SELECT version FROM schema_migrations")
    rescue StandardError
      []
    end

    # rubocop:disable Metrics/MethodLength
    def check_environment_configuration
      config = MigrationGuard.configuration

      if defined?(Rails) && Rails.respond_to?(:env)
        current_env = Rails.env.to_sym

        if config.enabled_environments.include?(current_env)
          envs = config.enabled_environments.join(", ")
          print_check("Environment configuration", :success, "enabled in: #{envs}")
        else
          add_warning("MigrationGuard disabled in current environment",
                      "Current: #{current_env}, Enabled in: #{config.enabled_environments.join(', ')}")
          print_check("Environment configuration", :warning, "disabled in #{current_env}")
        end
      else
        add_warning("Rails environment not detected",
                    "MigrationGuard is designed to work within a Rails application environment")
        print_check("Environment configuration", :warning, "Rails not loaded")
      end
    end
    # rubocop:enable Metrics/MethodLength

    def print_check(name, status, details = nil)
      symbol = case status
               when :success then colorizer.success("✓")
               when :warning then colorizer.warning("⚠")
               when :error then colorizer.error("✗")
               end

      line = "#{symbol} #{name}"
      line += ": #{details}" if details
      puts line # rubocop:disable Rails/Output
    end

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def print_summary
      puts # rubocop:disable Rails/Output
      puts colorizer.bold("=" * 50) # rubocop:disable Rails/Output

      if issues.any?
        puts colorizer.error("Issues Found:") # rubocop:disable Rails/Output
        issues.each_with_index do |(title, description), index|
          puts colorizer.error("#{index + 1}. #{title}:") # rubocop:disable Rails/Output
          puts "   #{description}" # rubocop:disable Rails/Output
          puts # rubocop:disable Rails/Output
        end
      end

      if warnings.any?
        puts colorizer.warning("Warnings:") # rubocop:disable Rails/Output
        warnings.each_with_index do |(title, description), index|
          puts colorizer.warning("#{index + 1}. #{title}:") # rubocop:disable Rails/Output
          puts "   #{description}" # rubocop:disable Rails/Output
          puts # rubocop:disable Rails/Output
        end
      end

      print_overall_status
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    # rubocop:disable Metrics/AbcSize
    def print_overall_status
      status = if issues.any?
                 colorizer.error("NEEDS ATTENTION (#{issues.size} issue(s))")
               elsif warnings.any?
                 colorizer.warning("OK WITH WARNINGS (#{warnings.size} warning(s))")
               else
                 colorizer.success("ALL SYSTEMS OK")
               end

      puts colorizer.bold("Overall Status: #{status}") # rubocop:disable Rails/Output
    end
    # rubocop:enable Metrics/AbcSize

    def add_issue(title, description)
      issues << [title, description]
    end

    def add_warning(title, description)
      warnings << [title, description]
    end

    def days_old(timestamp)
      ((Time.current - timestamp) / 1.day).round
    end
  end
  # rubocop:enable Metrics/ClassLength
end
