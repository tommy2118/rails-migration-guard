# frozen_string_literal: true

require_relative "colorizer"
require_relative "migration_extension"

module MigrationGuard
  class Reporter # rubocop:disable Metrics/ClassLength
    def initialize
      @git_integration = GitIntegration.new
      MigrationGuard::Logger.debug("Initialized Reporter")
    end

    def orphaned_migrations
      @orphaned_migrations ||= begin
        MigrationGuard::Logger.debug("Calculating orphaned migrations")
        if MigrationGuard.configuration.target_branches
          orphaned_from_all_branches
        else
          orphaned_from_main_branch
        end
      end
    end

    def orphaned_from_main_branch
      trunk_versions = @git_integration.migration_versions_in_trunk
      MigrationGuard::Logger.debug("Checking for orphaned migrations against main branch",
                                   trunk_version_count: trunk_versions.size)

      orphaned = MigrationGuardRecord
                 .applied
                 .reject { |record| trunk_versions.include?(record.version) }

      MigrationGuard::Logger.info("Found orphaned migrations", count: orphaned.size) if orphaned.any?
      orphaned
    end

    def orphaned_from_all_branches
      branch_versions = @git_integration.migration_versions_in_branches
      all_trunk_versions = branch_versions.values.flatten.uniq
      MigrationGuard::Logger.debug("Checking for orphaned migrations against all branches",
                                   branches: branch_versions.keys,
                                   total_versions: all_trunk_versions.size)

      orphaned = MigrationGuardRecord
                 .applied
                 .reject { |record| all_trunk_versions.include?(record.version) }

      MigrationGuard::Logger.info("Found orphaned migrations", count: orphaned.size) if orphaned.any?
      orphaned
    end

    def missing_migrations
      @missing_migrations ||= begin
        MigrationGuard::Logger.debug("Calculating missing migrations")
        if MigrationGuard.configuration.target_branches
          missing_from_any_branch
        else
          missing_from_main_branch
        end
      end
    end

    def missing_from_main_branch
      trunk_versions = @git_integration.migration_versions_in_trunk
      applied_versions = MigrationGuardRecord.pluck(:version)

      missing = trunk_versions - applied_versions
      MigrationGuard::Logger.info("Found missing migrations", count: missing.size) if missing.any?
      missing
    end

    def missing_from_any_branch
      branch_versions = @git_integration.migration_versions_in_branches
      applied_versions = MigrationGuardRecord.pluck(:version)
      MigrationGuard::Logger.debug("Checking missing migrations across branches",
                                   applied_count: applied_versions.size)

      missing_by_branch = calculate_missing_by_branch(branch_versions, applied_versions)
      log_missing_branches_summary(missing_by_branch)
      missing_by_branch
    end

    def status_report
      if MigrationGuard.configuration.target_branches
        multi_branch_status_report
      else
        single_branch_status_report
      end
    end

    def single_branch_status_report
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

    def multi_branch_status_report
      target_branches = @git_integration.target_branches
      missing = missing_migrations

      {
        current_branch: @git_integration.current_branch,
        target_branches: target_branches,
        synced_count: synced_count,
        orphaned_count: orphaned_migrations.size,
        missing_by_branch: missing,
        orphaned_migrations: orphaned_migrations_details,
        missing_migrations: missing.values.flatten.uniq
      }
    end

    def format_status_output
      MigrationGuard::Logger.debug("Formatting status output")
      report = status_report
      output = []

      add_header(output, report)
      add_summary_section(output, report)
      add_orphaned_section(output, report) if report[:orphaned_count].positive?

      if report[:target_branches]
        add_multi_branch_missing_section(output, report) if report[:missing_by_branch]&.any?
      elsif report[:missing_count].positive?
        add_missing_section(output, report)
      end

      output.join("\n")
    end

    def summary_line # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      report = status_report

      if report[:orphaned_count].positive?
        count = report[:orphaned_count]
        branch = report[:current_branch]
        "MigrationGuard: #{count} orphaned #{pluralize_migration(count)} detected on branch '#{branch}'"
      elsif report[:target_branches]
        if report[:missing_by_branch]&.any?
          total_missing = report[:missing_migrations].size
          branches = report[:missing_by_branch].keys.join(", ")
          "MigrationGuard: #{total_missing} missing #{pluralize_migration(total_missing)} from branches: #{branches}"
        else
          branches = report[:target_branches].join(", ")
          "MigrationGuard: All migrations synced with branches: #{branches}"
        end
      elsif report[:missing_count].positive?
        count = report[:missing_count]
        "MigrationGuard: #{count} missing #{pluralize_migration(count)} from #{report[:main_branch]}"
      else
        "MigrationGuard: All migrations synced with #{report[:main_branch]}"
      end
    end

    private

    def calculate_missing_by_branch(branch_versions, applied_versions)
      missing_by_branch = {}
      branch_versions.each do |branch, versions|
        next unless versions.is_a?(Array)

        missing = versions - applied_versions
        if missing.any?
          missing_by_branch[branch] = missing
          MigrationGuard::Logger.debug("Missing migrations in branch", branch: branch, count: missing.size)
        end
      end
      missing_by_branch
    end

    def log_missing_branches_summary(missing_by_branch)
      return unless missing_by_branch.any?

      MigrationGuard::Logger.info("Found missing migrations in branches",
                                  branches: missing_by_branch.keys)
    end

    def synced_count
      if MigrationGuard.configuration.target_branches
        branch_versions = @git_integration.migration_versions_in_branches
        all_trunk_versions = branch_versions.values
                                            .select { |v| v.is_a?(Array) }
                                            .flatten
                                            .uniq
        MigrationGuardRecord.applied.where(version: all_trunk_versions).count
      else
        trunk_versions = @git_integration.migration_versions_in_trunk
        MigrationGuardRecord.applied.where(version: trunk_versions).count
      end
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

    def add_header(output, report)
      output << ("═" * 55)
      if report[:target_branches]
        branches_text = report[:target_branches].join(", ")
        output << Colorizer.bold("Migration Status (branches: #{branches_text})")
      else
        output << Colorizer.bold("Migration Status (#{report[:main_branch]} branch)")
      end

      # Add sandbox mode indicator
      if MigrationGuard.configuration.sandbox_mode
        output << Colorizer.warning(MigrationGuard::SandboxMessages::START)
      end

      output << ("═" * 55)
    end

    def add_summary_section(output, report)
      add_sync_status(output, report)
      add_synced_count(output, report)
      add_orphaned_count(output, report)
      add_missing_count(output, report)
    end

    def add_synced_count(output, report)
      output << Colorizer.format_status_line(
        Colorizer.format_checkmark,
        "Synced",
        report[:synced_count],
        :synced
      )
    end

    def add_orphaned_count(output, report)
      return unless report[:orphaned_count].positive?

      orphaned_line = Colorizer.format_status_line(
        Colorizer.format_warning_symbol,
        "Orphaned",
        report[:orphaned_count],
        :orphaned
      )
      output << "#{orphaned_line} (local only)"
    end

    def add_missing_count(output, report) # rubocop:disable Metrics/MethodLength
      if report[:target_branches]
        return unless report[:missing_by_branch]&.any?

        total_missing = report[:missing_migrations].size
        missing_line = Colorizer.format_status_line(
          Colorizer.format_error_symbol,
          "Missing",
          total_missing,
          :missing
        )
        output << "#{missing_line} (in target branches, not local)"
      else
        return unless report[:missing_count].positive?

        missing_line = Colorizer.format_status_line(
          Colorizer.format_error_symbol,
          "Missing",
          report[:missing_count],
          :missing
        )
        output << "#{missing_line} (in trunk, not local)"
      end
    end

    def add_sync_status(output, report) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      if report[:target_branches]
        return unless report[:orphaned_count].zero? && report[:missing_by_branch]&.empty?

        branches = report[:target_branches].join(", ")
        output << Colorizer.format_status_line(
          Colorizer.format_checkmark,
          "All migrations synced with #{branches}",
          report[:synced_count],
          :synced
        )
      else
        return unless report[:orphaned_count].zero? && report[:missing_count].zero?

        output << Colorizer.format_status_line(
          Colorizer.format_checkmark,
          "All migrations synced with #{report[:main_branch]}",
          report[:synced_count],
          :synced
        )
      end
    end

    def add_orphaned_section(output, report)
      output << ""
      output << Colorizer.warning("Orphaned Migrations:")
      report[:orphaned_migrations].each do |migration|
        output << format_orphaned_migration(migration)
      end
      output << ""
      output << Colorizer.info("Run `rails db:migration:rollback_orphaned` to clean up")
    end

    def add_missing_section(output, report)
      output << ""
      output << Colorizer.error("Missing Migrations:")
      report[:missing_migrations].each do |version|
        output << "  #{version}"
      end
      output << ""
      output << Colorizer.info("Run `rails db:migrate` to apply missing migrations")
    end

    def add_multi_branch_missing_section(output, report)
      output << ""
      output << Colorizer.error("Missing Migrations by Branch:")

      report[:missing_by_branch].each do |branch, versions|
        output << ""
        output << "  #{Colorizer.bold(branch)}:"
        versions.each do |version|
          output << "    #{version}"
        end
      end

      output << ""
      output << Colorizer.info("Run `rails db:migrate` to apply missing migrations")
    end
  end
end
