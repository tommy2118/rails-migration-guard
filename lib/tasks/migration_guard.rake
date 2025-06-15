# frozen_string_literal: true

require "migration_guard/rake_tasks"

namespace :db do
  namespace :migration do
    desc "Show the status of migrations relative to the main branch"
    task status: :environment do
      MigrationGuard::RakeTasks.status
    end

    desc "Roll back orphaned migrations interactively"
    task rollback_orphaned: :environment do
      MigrationGuard::RakeTasks.rollback_orphaned
    end

    desc "Roll back all orphaned migrations without confirmation"
    task rollback_all_orphaned: :environment do
      MigrationGuard::RakeTasks.rollback_all
    end

    desc "Roll back a specific migration by version"
    task rollback_specific: :environment do
      MigrationGuard::RakeTasks.rollback_specific(ENV.fetch("VERSION", nil))
    end

    desc "Clean up old migration tracking records"
    task cleanup: :environment do
      MigrationGuard::RakeTasks.cleanup(force: ENV["FORCE"] == "true")
    end

    desc "Run diagnostics on MigrationGuard setup"
    task doctor: :environment do
      MigrationGuard::RakeTasks.doctor
    end
  end
end
