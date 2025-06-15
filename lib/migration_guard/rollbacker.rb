# frozen_string_literal: true

require_relative "colorizer"

module MigrationGuard
  class Rollbacker
    def initialize(interactive: true)
      @interactive = interactive
      @git_integration = GitIntegration.new
      @reporter = Reporter.new
    end

    def rollback_orphaned
      orphaned = @reporter.orphaned_migrations
      
      if orphaned.empty?
        output_message Colorizer.success("No orphaned migrations found.")
        return
      end
      
      output_message Colorizer.warning("Found #{orphaned.size} orphaned #{pluralize_migration(orphaned.size)}:")
      output_message ""
      
      orphaned.each do |migration|
        output_message "  #{migration.version} - #{migration.branch || 'unknown branch'}"
      end
      
      output_message ""
      
      if @interactive
        print "Do you want to roll back these migrations? (y/n): "
        response = gets.chomp.downcase
        
        if response != 'y'
          output_message Colorizer.info("Rollback cancelled.")
          return
        end
      end
      
      orphaned.each do |migration|
        rollback_migration(migration)
      end
      
      output_message ""
      count = orphaned.size
      message = "#{Colorizer.format_checkmark} Successfully rolled back #{count} #{pluralize_migration(count)}"
      output_message Colorizer.success(message)
    end

    def rollback_specific(version)
      migration = MigrationGuardRecord.find_by(version: version)

      raise MigrationNotFoundError, "Migration #{version} not found" unless migration

      if migration.rolled_back?
        output_message Colorizer.warning("Migration #{version} is already rolled back.")
        return
      end

      rollback_migration(migration)
      output_message Colorizer.success("#{Colorizer.format_checkmark} Successfully rolled back #{version}")
    end

    def rollback_all_orphaned
      orphaned = @reporter.orphaned_migrations
      
      if orphaned.empty?
        output_message Colorizer.success("No orphaned migrations found.")
        return
      end
      
      output_message Colorizer.warning("Found #{orphaned.size} orphaned #{pluralize_migration(orphaned.size)}:")
      orphaned.each do |migration|
        output_message "  #{migration.version}"
      end
      
      output_message ""
      
      if @interactive
        print "Do you want to roll back ALL orphaned migrations? (y/n): "
        response = gets.chomp.downcase
        
        if response != 'y'
          output_message Colorizer.info("Rollback cancelled.")
          return
        end
      end
      
      success_count = 0
      failure_count = 0
      
      orphaned.each do |migration|
        begin
          rollback_migration(migration)
          success_count += 1
        rescue StandardError => e
          output_message Colorizer.error("Failed to roll back #{migration.version}: #{e.message}")
          failure_count += 1
        end
      end
      
      if failure_count > 0
        output_message ""
        output_message Colorizer.warning("Rolled back #{success_count} migration(s) with #{failure_count} failure(s)")
      else
        output_message ""
        output_message Colorizer.success("#{Colorizer.format_checkmark} All orphaned migrations rolled back successfully")
      end
    end

    private

    def rollback_migration(migration)
      output_message Colorizer.info("Rolling back #{migration.version}...")
      
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

    def output_message(message)
      Rails.logger.debug message
    end
  end
end
