# frozen_string_literal: true

require_relative "colorizer"
require_relative "migration_extension"
require_relative "status_presenter"

module MigrationGuard
  class Reporter
    def initialize(git_integration: GitIntegration.new)
      @git_integration = git_integration
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
      StatusPresenter.new.format_status_output(status_report)
    end

    def summary_line
      StatusPresenter.new.summary_line(status_report)
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
  end
end
