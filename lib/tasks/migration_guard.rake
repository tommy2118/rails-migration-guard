# frozen_string_literal: true

namespace :db do
  namespace :migration do
    desc "Show the status of migrations relative to the main branch"
    task status: :environment do
      unless MigrationGuard.enabled?
        puts "MigrationGuard is not enabled in #{Rails.env}"
        exit 0
      end

      reporter = MigrationGuard::Reporter.new
      puts reporter.format_status_output
    end

    desc "Roll back orphaned migrations interactively"
    task rollback_orphaned: :environment do
      unless MigrationGuard.enabled?
        puts "MigrationGuard is not enabled in #{Rails.env}"
        exit 0
      end

      rollbacker = MigrationGuard::Rollbacker.new
      rollbacker.rollback_orphaned
    end

    desc "Roll back all orphaned migrations (use with caution)"
    task rollback_all_orphaned: :environment do
      unless MigrationGuard.enabled?
        puts "MigrationGuard is not enabled in #{Rails.env}"
        exit 0
      end

      rollbacker = MigrationGuard::Rollbacker.new
      rollbacker.rollback_all_orphaned
    end

    desc "Check for migration issues (for CI/CD)"
    task check: :environment do
      unless MigrationGuard.enabled?
        puts "MigrationGuard is not enabled in #{Rails.env}"
        exit 0
      end

      reporter = MigrationGuard::Reporter.new
      report = reporter.status_report

      if report[:orphaned_count] > 0
        puts "ERROR: Found #{report[:orphaned_count]} orphaned migration(s)"
        puts reporter.format_status_output
        
        if MigrationGuard.configuration.block_deploy_with_orphans
          exit 1
        end
      elsif report[:missing_count] > 0
        puts "WARNING: Found #{report[:missing_count]} missing migration(s)"
        puts reporter.format_status_output
      else
        puts "✓ All migrations synced with #{report[:main_branch]}"
      end
    end

    desc "Clean up old migration guard records"
    task cleanup: :environment do
      unless MigrationGuard.enabled?
        puts "MigrationGuard is not enabled in #{Rails.env}"
        exit 0
      end

      days = ENV["DAYS"] || MigrationGuard.configuration.cleanup_after_days
      
      old_records = MigrationGuard::MigrationGuardRecord
        .where(status: "rolled_back")
        .where("created_at < ?", days.to_i.days.ago)
      
      count = old_records.count
      
      if count > 0
        print "Delete #{count} old rolled back migration record(s)? (y/n): "
        response = STDIN.gets.chomp.downcase
        
        if response == 'y'
          old_records.destroy_all
          puts "✓ Deleted #{count} record(s)"
        else
          puts "Cleanup cancelled"
        end
      else
        puts "No old records to clean up"
      end
    end
  end

  # Override the standard migrate task to show status after migration
  task :migrate do
    if MigrationGuard.enabled? && MigrationGuard.configuration.warn_on_switch
      at_exit do
        reporter = MigrationGuard::Reporter.new
        if reporter.orphaned_migrations.any?
          puts ""
          puts reporter.summary_line
        end
      end
    end
  end
end