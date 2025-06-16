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
      
      begin
        # Execute the down migration
        ActiveRecord::Migration.execute_down(migration.version)
        MigrationGuard::Logger.debug("Down migration executed successfully", version: migration.version)

        # Update the record status
        migration.update!(status: "rolled_back")
        MigrationGuard::Logger.info("Migration rolled back successfully", version: migration.version)
      rescue StandardError => e
        MigrationGuard::Logger.error("Rollback failed", version: migration.version, error: e.message)
        raise RollbackError, "Failed to roll back migration #{migration.version}: #{e.message}"
      end
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
  end
end
