# frozen_string_literal: true

module MigrationGuard
  class Rollbacker
    def initialize(interactive: true)
      @interactive = interactive
      @git_integration = GitIntegration.new
      @reporter = Reporter.new
    end

    def rollback_orphaned
      orphaned = @reporter.orphaned_migrations
      return if handle_no_orphaned_migrations?(orphaned)

      display_orphaned_migrations(orphaned)
      return unless confirm_rollback?("Do you want to roll back these migrations? (y/n): ")

      orphaned.each { |migration| rollback_migration(migration) }

      Rails.logger.debug ""
      Rails.logger.debug { "✓ Successfully rolled back #{orphaned.size} #{pluralize_migration(orphaned.size)}" }
    end

    def rollback_specific(version)
      migration = MigrationGuardRecord.find_by(version: version)

      raise MigrationNotFoundError, "Migration #{version} not found" unless migration

      if migration.rolled_back?
        Rails.logger.debug { "Migration #{version} is already rolled back." }
        return
      end

      rollback_migration(migration)
      Rails.logger.debug { "✓ Successfully rolled back #{version}" }
    end

    def rollback_all_orphaned
      orphaned = @reporter.orphaned_migrations
      return if handle_no_orphaned_migrations?(orphaned)

      display_orphaned_migrations(orphaned, simple_format: true)
      return unless confirm_rollback?("Do you want to roll back ALL orphaned migrations? (y/n): ")

      rollback_migrations_with_error_handling(orphaned)
    end

    private

    def rollback_migration(migration)
      Rails.logger.debug { "Rolling back #{migration.version}..." }

      begin
        # Execute the down migration
        ActiveRecord::Migration.execute_down(migration.version)

        # Update the record status
        migration.update!(status: "rolled_back")
      rescue StandardError => e
        raise RollbackError, "Failed to roll back migration #{migration.version}: #{e.message}"
      end
    end

    def pluralize_migration(count)
      count == 1 ? "migration" : "migrations"
    end

    def handle_no_orphaned_migrations?(orphaned)
      if orphaned.empty?
        Rails.logger.debug "No orphaned migrations found."
        true
      else
        false
      end
    end

    def display_orphaned_migrations(orphaned, simple_format: false)
      Rails.logger.debug { "Found #{orphaned.size} orphaned #{pluralize_migration(orphaned.size)}:" }
      Rails.logger.debug ""

      display_migration_list(orphaned, simple_format)

      Rails.logger.debug ""
    end

    def display_migration_list(orphaned, simple_format)
      orphaned.each do |migration|
        message = simple_format ? migration.version : "#{migration.version} - #{migration.branch || 'unknown branch'}"
        Rails.logger.debug { "  #{message}" }
      end
    end

    def confirm_rollback?(prompt)
      return true unless @interactive

      Rails.logger.debug prompt
      response = gets.chomp.downcase

      if response == "y"
        true
      else
        Rails.logger.debug "Rollback cancelled."
        false
      end
    end

    def rollback_migrations_with_error_handling(orphaned)
      success_count = 0
      failure_count = 0

      orphaned.each do |migration|
        rollback_migration(migration)
        success_count += 1
      rescue StandardError => e
        Rails.logger.debug { "Failed to roll back #{migration.version}: #{e.message}" }
        failure_count += 1
      end

      Rails.logger.debug ""
      if failure_count.positive?
        Rails.logger.debug { "Rolled back #{success_count} migration(s) with #{failure_count} failure(s)" }
      else
        Rails.logger.debug "✓ All orphaned migrations rolled back successfully"
      end
    end
  end
end
