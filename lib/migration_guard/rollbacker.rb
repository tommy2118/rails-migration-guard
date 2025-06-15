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
      
      if orphaned.empty?
        puts "No orphaned migrations found."
        return
      end
      
      puts "Found #{orphaned.size} orphaned #{pluralize_migration(orphaned.size)}:"
      puts ""
      
      orphaned.each do |migration|
        puts "  #{migration.version} - #{migration.branch || 'unknown branch'}"
      end
      
      puts ""
      
      if @interactive
        print "Do you want to roll back these migrations? (y/n): "
        response = gets.chomp.downcase
        
        if response != 'y'
          puts "Rollback cancelled."
          return
        end
      end
      
      orphaned.each do |migration|
        rollback_migration(migration)
      end
      
      puts ""
      puts "✓ Successfully rolled back #{orphaned.size} #{pluralize_migration(orphaned.size)}"
    end

    def rollback_specific(version)
      migration = MigrationGuardRecord.find_by(version: version)
      
      raise MigrationNotFoundError, "Migration #{version} not found" unless migration
      
      if migration.rolled_back?
        puts "Migration #{version} is already rolled back."
        return
      end
      
      rollback_migration(migration)
      puts "✓ Successfully rolled back #{version}"
    end

    def rollback_all_orphaned
      orphaned = @reporter.orphaned_migrations
      
      if orphaned.empty?
        puts "No orphaned migrations found."
        return
      end
      
      puts "Found #{orphaned.size} orphaned #{pluralize_migration(orphaned.size)}:"
      orphaned.each do |migration|
        puts "  #{migration.version}"
      end
      
      puts ""
      
      if @interactive
        print "Do you want to roll back ALL orphaned migrations? (y/n): "
        response = gets.chomp.downcase
        
        if response != 'y'
          puts "Rollback cancelled."
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
          puts "Failed to roll back #{migration.version}: #{e.message}"
          failure_count += 1
        end
      end
      
      if failure_count > 0
        puts ""
        puts "Rolled back #{success_count} migration(s) with #{failure_count} failure(s)"
      else
        puts ""
        puts "✓ All orphaned migrations rolled back successfully"
      end
    end

    private

    def rollback_migration(migration)
      puts "Rolling back #{migration.version}..."
      
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
  end
end