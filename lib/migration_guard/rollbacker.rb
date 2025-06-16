# frozen_string_literal: true

require_relative "colorizer"

module MigrationGuard
  class Rollbacker
    def initialize(interactive: true)
      @interactive = interactive
      @git_integration = GitIntegration.new
      @reporter = Reporter.new
      MigrationGuard::Logger.debug("Initialized Rollbacker", interactive: interactive)
    end

    def rollback_orphaned
      MigrationGuard::Logger.info("Starting rollback of orphaned migrations")
      orphaned = @reporter.orphaned_migrations

      if orphaned.empty?
        MigrationGuard::Logger.debug("No orphaned migrations found")
        return display_no_orphaned_migrations
      end

      MigrationGuard::Logger.debug("Found orphaned migrations", count: orphaned.size)
      display_orphaned_list(orphaned)
      return unless confirm_rollback?("Do you want to roll back these migrations? (y/n): ")

      execute_rollbacks(orphaned)
      display_rollback_success(orphaned.size)
    end

    def rollback_specific(version)
      MigrationGuard::Logger.info("Starting rollback of specific migration", version: version)
      migration = MigrationGuardRecord.find_by(version: version)

      unless migration
        MigrationGuard::Logger.error("Migration not found", version: version)
        raise MigrationNotFoundError, "Migration #{version} not found"
      end

      if migration.rolled_back?
        MigrationGuard::Logger.warn("Migration already rolled back", version: version)
        output_message Colorizer.warning("Migration #{version} is already rolled back.")
        return
      end

      rollback_migration(migration)
      output_message Colorizer.success("#{Colorizer.format_checkmark} Successfully rolled back #{version}")
    end

    def rollback_all_orphaned
      orphaned = @reporter.orphaned_migrations
      return display_no_orphaned_migrations if orphaned.empty?

      display_orphaned_list_simple(orphaned)
      return unless confirm_rollback?("Do you want to roll back ALL orphaned migrations? (y/n): ")

      execute_rollbacks_with_error_handling(orphaned)
    end

    private

    def rollback_migration(migration)
      output_message Colorizer.info("Rolling back #{migration.version}...")
      MigrationGuard::Logger.debug("Executing rollback", version: migration.version)

      execute_migration_rollback(migration)
      update_migration_status(migration)
    rescue StandardError => e
      handle_rollback_error(migration, e)
    end

    def execute_migration_rollback(migration)
      version = migration.version.to_i
      context = create_migration_context

      validate_migration_applied(context, version, migration.version)
      target_migration = find_target_migration(context, version, migration.version)
      execute_down_migration(target_migration)

      MigrationGuard::Logger.debug("Down migration executed successfully", version: migration.version)
    rescue RollbackError
      raise
    rescue StandardError => e
      raise RollbackError, "Failed to execute down migration for #{migration.version}: #{e.message}"
    end

    def create_migration_context
      migration_paths = migrations_paths
      ActiveRecord::MigrationContext.new(migration_paths)
    end

    def validate_migration_applied(context, version, version_string)
      applied_versions = context.get_all_versions
      return if applied_versions.include?(version)

      raise RollbackError, "Migration #{version_string} is not currently applied"
    end

    def find_target_migration(context, version, version_string)
      target_migration = context.migrations.find { |m| m.version == version }
      return target_migration if target_migration

      raise RollbackError, "Migration file for version #{version_string} not found"
    end

    def execute_down_migration(target_migration)
      target_migration.migrate(:down) if target_migration.respond_to?(:migrate)
    end

    def update_migration_status(migration)
      migration.update!(status: "rolled_back")
      MigrationGuard::Logger.info("Migration rolled back successfully", version: migration.version)
    end

    def handle_rollback_error(migration, error)
      MigrationGuard::Logger.error("Rollback failed", version: migration.version, error: error.message)
      raise RollbackError, "Failed to roll back migration #{migration.version}: #{error.message}"
    end

    def pluralize_migration(count)
      count == 1 ? "migration" : "migrations"
    end

    def output_message(message)
      Rails.logger.debug message
    end

    def display_no_orphaned_migrations
      output_message Colorizer.success("No orphaned migrations found.")
    end

    def display_orphaned_list(orphaned)
      output_message Colorizer.warning("Found #{orphaned.size} orphaned #{pluralize_migration(orphaned.size)}:")
      output_message ""
      orphaned.each do |migration|
        output_message "  #{migration.version} - #{migration.branch || 'unknown branch'}"
      end
      output_message ""
    end

    def display_orphaned_list_simple(orphaned)
      output_message Colorizer.warning("Found #{orphaned.size} orphaned #{pluralize_migration(orphaned.size)}:")
      orphaned.each do |migration|
        output_message "  #{migration.version}"
      end
      output_message ""
    end

    def confirm_rollback?(prompt)
      return true unless @interactive

      Rails.logger.debug prompt
      response = gets.chomp.downcase
      return true if response == "y"

      output_message Colorizer.info("Rollback cancelled.")
      false
    end

    def execute_rollbacks(orphaned)
      orphaned.each { |migration| rollback_migration(migration) }
    end

    def display_rollback_success(count)
      output_message ""
      message = "#{Colorizer.format_checkmark} Successfully rolled back #{count} #{pluralize_migration(count)}"
      output_message Colorizer.success(message)
    end

    def execute_rollbacks_with_error_handling(orphaned)
      success_count = 0
      failure_count = 0

      orphaned.each do |migration|
        rollback_migration(migration)
        success_count += 1
      rescue StandardError => e
        output_message Colorizer.error("Failed to roll back #{migration.version}: #{e.message}")
        failure_count += 1
      end

      display_batch_rollback_results(success_count, failure_count)
    end

    def display_batch_rollback_results(success_count, failure_count)
      output_message ""
      if failure_count.positive?
        message = "Rolled back #{success_count} migration(s) with #{failure_count} failure(s)"
        output_message Colorizer.warning(message)
      else
        message = "#{Colorizer.format_checkmark} All orphaned migrations rolled back successfully"
        output_message Colorizer.success(message)
      end
    end

    def migrations_paths
      return ["db/migrate"] unless defined?(Rails) && Rails.respond_to?(:application)
      return ["db/migrate"] unless Rails.application

      begin
        config_paths = Rails.application.config.paths
        return ["db/migrate"] unless config_paths.respond_to?(:[])

        migrate_paths = config_paths["db/migrate"]
        migrate_paths || ["db/migrate"]
      rescue StandardError
        ["db/migrate"]
      end
    end

    def migration_file_exists?(version)
      migration_paths = migrations_paths
      migration_paths.any? do |path|
        Dir.glob(File.join(path, "*_*.rb")).any? { |file| File.basename(file).start_with?(version.to_s) }
      end
    end
  end
end
