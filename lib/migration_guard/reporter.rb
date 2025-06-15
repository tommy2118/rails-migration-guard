# frozen_string_literal: true

module MigrationGuard
  class Reporter
    def initialize
      @git_integration = GitIntegration.new
    end

    def orphaned_migrations
      @orphaned_migrations ||= begin
        trunk_versions = @git_integration.migration_versions_in_trunk

        MigrationGuardRecord
          .applied
          .reject { |record| trunk_versions.include?(record.version) }
      end
    end

    def missing_migrations
      @missing_migrations ||= begin
        trunk_versions = @git_integration.migration_versions_in_trunk
        applied_versions = MigrationGuardRecord.pluck(:version)

        trunk_versions - applied_versions
      end
    end

    def status_report
      {
        current_branch: @git_integration.current_branch,
        main_branch: @git_integration.main_branch,
        synced_count: synced_count,
        orphaned_count: orphaned_migrations.size,
        missing_count: missing_migrations.size,
        orphaned_migrations: orphaned_migrations_details,
        missing_migrations: missing_migrations
      }
    end

    def format_status_output
      report = status_report
      output = []

      output << ("═" * 55)
      output << "Migration Status (#{report[:main_branch]} branch)"
      output << ("═" * 55)

      add_summary_section(output, report)
      add_orphaned_section(output, report) if report[:orphaned_count].positive?
      add_missing_section(output, report) if report[:missing_count].positive?

      output.join("\n")
    end

    def summary_line
      report = status_report

      if report[:orphaned_count].positive?
        count = report[:orphaned_count]
        branch = report[:current_branch]
        "MigrationGuard: #{count} orphaned #{pluralize_migration(count)} detected on branch '#{branch}'"
      elsif report[:missing_count].positive?
        count = report[:missing_count]
        "MigrationGuard: #{count} missing #{pluralize_migration(count)} from #{report[:main_branch]}"
      else
        "MigrationGuard: All migrations synced with #{report[:main_branch]}"
      end
    end

    private

    def synced_count
      trunk_versions = @git_integration.migration_versions_in_trunk
      MigrationGuardRecord.applied.where(version: trunk_versions).count
    end

    def orphaned_migrations_details
      orphaned_migrations.map do |record|
        {
          version: record.version,
          branch: record.branch,
          author: record.author,
          status: record.status,
          created_at: record.created_at,
          age_in_days: ((Time.current - record.created_at) / 1.day).round
        }
      end
    end

    def format_orphaned_migration(migration)
      lines = []
      lines << "  #{migration[:version]}"
      lines << "    Branch: #{migration[:branch]}" if migration[:branch]
      lines << "    Author: #{migration[:author]}" if migration[:author]
      lines << "    Age: #{migration[:age_in_days]} days"
      lines.join("\n")
    end

    def pluralize_migration(count)
      count == 1 ? "migration" : "migrations"
    end

    def add_summary_section(output, report)
      add_sync_status(output, report)
      add_count_line(output, "✓ Synced:   ", report[:synced_count])
      if report[:orphaned_count].positive?
        add_count_line(output, "⚠ Orphaned: ", report[:orphaned_count],
                       " (local only)")
      end
      if report[:missing_count].positive? # rubocop:disable Style/GuardClause
        add_count_line(output, "✗ Missing:  ", report[:missing_count],
                       " (in trunk, not local)")
      end
    end

    def add_sync_status(output, report)
      return unless report[:orphaned_count].zero? && report[:missing_count].zero?

      output << "✓ All migrations synced with #{report[:main_branch]}"
    end

    def add_count_line(output, prefix, count, suffix = "")
      output << "#{prefix} #{count} #{pluralize_migration(count)}#{suffix}"
    end

    def add_orphaned_section(output, report)
      output << ""
      output << "Orphaned Migrations:"
      report[:orphaned_migrations].each do |migration|
        output << format_orphaned_migration(migration)
      end
      output << ""
      output << "Run `rails db:migration:rollback_orphaned` to clean up"
    end

    def add_missing_section(output, report)
      output << ""
      output << "Missing Migrations:"
      report[:missing_migrations].each do |version|
        output << "  #{version}"
      end
      output << ""
      output << "Run `rails db:migrate` to apply missing migrations"
    end
  end
end
