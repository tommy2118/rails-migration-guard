# frozen_string_literal: true

require_relative "colorizer"
require_relative "interactive_mode"
require_relative "schema_inspector"
require_relative "rollback_presenter"

module MigrationGuard
  class Rollbacker
    include SchemaInspector

    def initialize(interactive: true, git_integration: GitIntegration.new, reporter: Reporter.new)
      @interactive = InteractiveMode.interactive?(requested_interactive: interactive)
      @git_integration = git_integration
      @reporter = reporter
      @presenter = RollbackPresenter.new

      InteractiveMode.log_tty_detection(interactive, @interactive, :migration_guard_logger)

      MigrationGuard::Logger.debug("Initialized Rollbacker", interactive: @interactive)
    end

    def rollback_orphaned
      MigrationGuard::Logger.info("Starting rollback of orphaned migrations")
      orphaned = @reporter.orphaned_migrations

      if orphaned.empty?
        MigrationGuard::Logger.debug("No orphaned migrations found")
        return @presenter.display_no_orphaned_migrations
      end

      MigrationGuard::Logger.debug("Found orphaned migrations", count: orphaned.size)
      @presenter.display_orphaned_list(orphaned)
      return unless confirm_rollback?("Do you want to roll back these migrations? (y/n): ")

      execute_rollbacks(orphaned)
      @presenter.display_rollback_success(orphaned.size)
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
        @presenter.display_already_rolled_back(version)
        return
      end

      rollback_migration(migration)
      @presenter.display_specific_rollback_success(version)
    end

    def rollback_all_orphaned
      orphaned = @reporter.orphaned_migrations
      return @presenter.display_no_orphaned_migrations if orphaned.empty?

      @presenter.display_orphaned_list_simple(orphaned)
      return unless confirm_rollback?("Do you want to roll back ALL orphaned migrations? (y/n): ")

      execute_rollbacks_with_error_handling(orphaned)
    end

    private

    def confirm_rollback?(prompt)
      return true unless @interactive

      @presenter.output_message(prompt)
      response = gets.chomp.downcase
      return true if response == "y"

      @presenter.output_message(Colorizer.info("Rollback cancelled."))
      false
    end

    def rollback_migration(migration)
      @presenter.display_rollback_progress(migration.version)
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

      remove_from_schema_migrations(migration.version)

      MigrationGuard::Logger.debug("Down migration executed successfully", version: migration.version)
    rescue RollbackError
      raise
    rescue StandardError => e
      raise RollbackError, "Failed to execute down migration for #{migration.version}: #{e.message}"
    end

    def create_migration_context
      migration_paths = migration_file_paths

      if ActiveRecord::MigrationContext.instance_method(:initialize).arity == 2
        ActiveRecord::MigrationContext.new(migration_paths, ActiveRecord::SchemaMigration)
      else
        ActiveRecord::MigrationContext.new(migration_paths)
      end
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
      migration.update!(status: MigrationGuardRecord::STATUS_ROLLED_BACK)
      MigrationGuard::Logger.info("Migration rolled back successfully", version: migration.version)
    end

    def handle_rollback_error(migration, error)
      MigrationGuard::Logger.error("Rollback failed", version: migration.version, error: error.message)
      @presenter.display_rollback_error(migration.version, error.message)
      raise RollbackError, "Failed to roll back migration #{migration.version}: #{error.message}"
    end

    def execute_rollbacks(orphaned)
      orphaned.each { |migration| rollback_migration(migration) }
    end

    def execute_rollbacks_with_error_handling(orphaned)
      success_count = 0
      failure_count = 0

      orphaned.each do |migration|
        rollback_migration(migration)
        success_count += 1
      rescue StandardError => e
        @presenter.display_batch_rollback_error(migration.version, e.message)
        failure_count += 1
      end

      @presenter.display_batch_rollback_results(success_count, failure_count)
    end

    def remove_from_schema_migrations(version)
      exists = ActiveRecord::Base.connection.select_value(
        ActiveRecord::Base.sanitize_sql(
          ["SELECT 1 FROM schema_migrations WHERE version = ? LIMIT 1", version.to_s]
        )
      )

      return unless exists

      ActiveRecord::Base.connection.execute(
        ActiveRecord::Base.sanitize_sql(
          ["DELETE FROM schema_migrations WHERE version = ?", version.to_s]
        )
      )

      MigrationGuard::Logger.debug("Removed version from schema_migrations", version: version)
    end

    def migration_file_exists?(version)
      migration_file_paths.any? do |path|
        Dir.glob(File.join(path, "*_*.rb")).any? { |file| File.basename(file).start_with?(version.to_s) }
      end
    end
  end
end
