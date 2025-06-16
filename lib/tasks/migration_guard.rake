# frozen_string_literal: true

# Lazy load to avoid loading ActiveRecord models before database setup
def ensure_migration_guard_loaded
  require "rails_migration_guard" unless defined?(MigrationGuard)
end

namespace :db do
  namespace :migration do
    desc "Show the status of migrations relative to the main branch"
    task status: :environment do
      ensure_migration_guard_loaded
      MigrationGuard::RakeTasks.status
    end

    desc "Roll back orphaned migrations interactively"
    task rollback_orphaned: :environment do
      ensure_migration_guard_loaded
      MigrationGuard::RakeTasks.rollback_orphaned
    end

    desc "Roll back all orphaned migrations without confirmation"
    task rollback_all_orphaned: :environment do
      ensure_migration_guard_loaded
      MigrationGuard::RakeTasks.rollback_all
    end

    desc "Roll back a specific migration by version"
    task rollback_specific: :environment do
      ensure_migration_guard_loaded
      MigrationGuard::RakeTasks.rollback_specific(ENV.fetch("VERSION", nil))
    end

    desc "Clean up old migration tracking records"
    task cleanup: :environment do
      ensure_migration_guard_loaded
      MigrationGuard::RakeTasks.cleanup(force: ENV["FORCE"] == "true")
    end

    desc "Run diagnostics on MigrationGuard setup"
    task doctor: :environment do
      ensure_migration_guard_loaded
      MigrationGuard::RakeTasks.doctor
    end

    desc "Check for migration changes after branch switch"
    task :check_branch_change, %i[previous_head new_head is_branch_checkout] => :environment do |_t, args|
      ensure_migration_guard_loaded
      MigrationGuard::RakeTasks.check_branch_change(
        args[:previous_head],
        args[:new_head],
        args[:is_branch_checkout]
      )
    end
  end
end
