# frozen_string_literal: true

require_relative "../check_printer"
require_relative "../schema_inspector"
require_relative "../time_formatters"

module MigrationGuard
  module Diagnostics
    # Checks orphaned, missing, stuck migrations, schema consistency,
    # and missing migration files
    class MigrationStateChecker
      include CheckPrinter
      include SchemaInspector
      include TimeFormatters

      def initialize(issues:, warnings:, output:, reporter:)
        @issues = issues
        @warnings = warnings
        @output = output
        @reporter = reporter
      end

      def run_checks
        check_orphaned_migrations
        check_missing_migrations
        check_stuck_migrations
        check_schema_consistency
        check_missing_migration_files
      end

      private

      def check_orphaned_migrations
        orphaned = @reporter.orphaned_migrations

        if orphaned.empty?
          print_check("Orphaned migrations", :success, "none found")
        else
          count = orphaned.size
          age_info = orphaned.map { |m| days_old(m.created_at) }.max
          @issues << ["Orphaned migrations detected",
                      "Run 'rails db:migration:rollback_orphaned' to clean up #{count} migration(s)"]
          print_check("Orphaned migrations", :error, "#{count} found (oldest: #{age_info} days)")
        end
      rescue StandardError => e
        @issues << ["Failed to check orphaned migrations", e.message]
        print_check("Orphaned migrations", :error)
      end

      def check_missing_migrations
        missing_report = @reporter.missing_migrations

        if missing_report.empty?
          print_check("Missing migrations", :success, "none found")
        else
          total_missing = missing_report.values.sum(&:size)
          branches = missing_report.keys.join(", ")
          @warnings << ["Missing migrations from trunk",
                        "Consider running 'rails db:migrate' or merging from #{branches}"]
          print_check("Missing migrations", :warning, "#{total_missing} found in: #{branches}")
        end
      rescue StandardError => e
        @issues << ["Failed to check missing migrations", e.message]
        print_check("Missing migrations", :error)
      end

      def check_stuck_migrations
        stuck = find_stuck_migrations

        if stuck.empty?
          print_check("Stuck migrations", :success, "none found")
        else
          report_stuck(stuck)
        end
      rescue StandardError => e
        @issues << ["Failed to check stuck migrations", e.message]
        print_check("Stuck migrations", :error)
      end

      def check_schema_consistency
        consistency_issues = analyze_schema_consistency

        if consistency_issues.empty?
          print_check("Schema consistency", :success, "schema_migrations in sync")
        else
          report_schema(consistency_issues)
        end
      rescue StandardError => e
        @issues << ["Schema consistency check failed", e.message]
        print_check("Schema consistency", :error)
      end

      def check_missing_migration_files
        missing_files = find_missing_migration_files

        if missing_files.empty?
          print_check("Migration files", :success, "all files present")
        else
          count = missing_files.size
          @issues << ["Migration file(s) missing",
                      "Cannot rollback migrations without their files: #{missing_files.map(&:version).join(', ')}"]
          print_check("Migration files", :error, "#{count} missing")
        end
      rescue StandardError => e
        @issues << ["Migration file check failed", e.message]
        print_check("Migration files", :error)
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
        MigrationGuard::MigrationGuardRecord.applied.reject { |r| schema_versions.include?(r.version) }
      end

      def find_rolled_back_in_schema(schema_versions)
        MigrationGuard::MigrationGuardRecord.rolled_back.select { |r| schema_versions.include?(r.version) }
      end

      def find_missing_migration_files
        all_records = MigrationGuard::MigrationGuardRecord.all
        paths = migration_file_paths

        all_records.reject { |record| migration_file_exists?(record.version, paths) }
      end

      def migration_file_exists?(version, paths)
        paths.any? { |path| Dir.glob(File.join(path, "#{version}_*.rb")).any? }
      end

      def days_old(timestamp) = ((Time.current - timestamp) / 1.day).round

      def find_stuck_migrations
        timeout = MigrationGuard.configuration.stuck_migration_timeout.minutes.ago
        MigrationGuard::MigrationGuardRecord.stuck_in_rollback(timeout)
      end

      def report_stuck(stuck)
        count = stuck.size
        oldest_time = stuck.minimum(:updated_at)
        time_stuck = format_time_since(oldest_time) if oldest_time

        versions = stuck.map(&:version).join(", ")
        @issues << ["Stuck migrations detected",
                    "Migration(s) stuck in rollback state: #{versions}. Run 'rails db:migration:recover' to fix"]

        details = "#{count} stuck"
        details += " (oldest: #{time_stuck})" if time_stuck
        print_check("Stuck migrations", :error, details)
      end

      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      def report_schema(consistency_issues)
        summary_parts = []

        if consistency_issues[:missing_from_schema]
          count = consistency_issues[:missing_from_schema].size
          summary_parts << "#{count} tracked as applied but missing from schema"
          versions = consistency_issues[:missing_from_schema].map(&:version).join(", ")
          @issues << ["Schema inconsistency detected",
                      "Migrations tracked as 'applied' but missing from schema_migrations: #{versions}"]
        end

        if consistency_issues[:rolled_back_in_schema]
          count = consistency_issues[:rolled_back_in_schema].size
          summary_parts << "#{count} rolled back but still in schema"
          versions = consistency_issues[:rolled_back_in_schema].map(&:version).join(", ")
          @issues << ["Rolled back migrations in schema",
                      "Migrations tracked as 'rolled_back' but still in schema_migrations: #{versions}"]
        end

        if consistency_issues[:untracked_in_schema]
          count = consistency_issues[:untracked_in_schema].size
          summary_parts << "#{count} in schema but not tracked"
          versions = consistency_issues[:untracked_in_schema].join(", ")
          @warnings << ["Untracked migrations in schema",
                        "Migrations in schema_migrations but not tracked: #{versions}"]
        end

        print_check("Schema consistency", :error, summary_parts.join(", "))
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

      def puts(*args)
        @output.send(:puts, *args)
      end
    end
  end
end
