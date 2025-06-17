# frozen_string_literal: true

# Lazy load to avoid loading ActiveRecord models before database setup
def ensure_migration_guard_loaded
  return if defined?(MigrationGuard::RakeTasks)

  require "rails_migration_guard"
  require "migration_guard/rake_tasks"
end

namespace :db do
  namespace :migration do
    desc "Show the status of migrations relative to the main branch"
    task status: :environment do
      ensure_migration_guard_loaded
      MigrationGuard::RakeTasks.status
    end

    desc "Roll back orphaned migrations interactively (use FORCE=true for non-interactive)"
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

    desc "Show migration history with optional filtering"
    task history: :environment do
      ensure_migration_guard_loaded

      options = {}
      options[:branch] = ENV["BRANCH"] if ENV["BRANCH"]
      options[:days] = ENV["DAYS"].to_i if ENV["DAYS"]
      options[:version] = ENV["VERSION"] if ENV["VERSION"]
      options[:author] = ENV["AUTHOR"] if ENV["AUTHOR"]
      options[:limit] = ENV["LIMIT"].to_i if ENV["LIMIT"]
      options[:format] = ENV["FORMAT"] if ENV["FORMAT"]

      MigrationGuard::RakeTasks.history(options)
    end

    desc "Show migration authors and their contribution summary"
    task authors: :environment do
      ensure_migration_guard_loaded
      MigrationGuard::RakeTasks.authors_report
    end

    desc "Analyze and recover from inconsistent migration states (use AUTO=true, FORCE=true, or NON_INTERACTIVE=true)"
    task recover: :environment do
      ensure_migration_guard_loaded
      MigrationGuard::RakeTasks.recover
    end

    desc "Run migration checks for CI/CD environments"
    task ci: :environment do
      ensure_migration_guard_loaded

      format = ENV["FORMAT"] || ENV["format"] || "text"
      strict = ENV["STRICT"] == "true" || ENV["strict"] == "true"
      strictness = ENV["STRICTNESS"] || ENV.fetch("strictness", nil)

      exit_code = MigrationGuard::RakeTasks.ci(
        format: format,
        strict: strict,
        strictness: strictness
      )

      exit(exit_code) if exit_code != 0
    end

    desc "Interactive setup assistant for new developers"
    task setup: :environment do
      ensure_migration_guard_loaded
      MigrationGuard::RakeTasks.setup
    end
  end
end
