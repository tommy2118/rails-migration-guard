# frozen_string_literal: true

require_relative "migration_guard_record"

module MigrationGuard
  class Tracker
    def track_migration(version, direction)
      return unless MigrationGuard.enabled?

      MigrationGuard::Logger.debug("Starting migration tracking", version: version, direction: direction)

      case direction
      when :up
        track_up_migration(version)
      when :down
        track_down_migration(version)
      end
    rescue StandardError => e
      MigrationGuard::Logger.error("Failed to track migration", error: e.message, version: version)
      nil
    end

    def current_branch
      output = `git rev-parse --abbrev-ref HEAD 2>/dev/null`.strip
      branch = output.empty? ? "unknown" : output
      MigrationGuard::Logger.debug("Current branch detected", branch: branch)
      branch
    end

    def current_author
      output = `git config user.email 2>/dev/null`.strip
      author = output.empty? ? "unknown" : output
      MigrationGuard::Logger.debug("Current author detected", author: author)
      author
    end

    def cleanup_old_records
      return unless MigrationGuard.configuration.auto_cleanup

      days_ago = MigrationGuard.configuration.cleanup_after_days
      MigrationGuard::Logger.debug("Starting cleanup of old records", days_ago: days_ago)

      count = MigrationGuardRecord
              .where(status: "rolled_back")
              .where(created_at: ...days_ago.days.ago)
              .destroy_all
              .size

      MigrationGuard::Logger.info("Cleaned up old migration records", count: count) if count.positive?
    end

    private

    def track_up_migration(version)
      record = MigrationGuardRecord.find_or_initialize_by(version: version)

      if record.persisted? && record.status == "applied"
        MigrationGuard::Logger.debug("Migration already tracked as applied", version: version)
        return
      end

      attributes = build_migration_attributes("applied")
      update_migration_record(record, version, attributes)
      cleanup_old_records
      record
    end

    def track_down_migration(version)
      record = MigrationGuardRecord.find_or_initialize_by(version: version)
      attributes = build_migration_attributes("rolled_back")
      update_migration_record(record, version, attributes)
      record
    end

    def track_branch?
      MigrationGuard.configuration.track_branch
    end

    def track_author?
      MigrationGuard.configuration.track_author
    end

    def build_migration_attributes(status)
      {
        status: status,
        branch: track_branch? ? current_branch : nil,
        author: track_author? ? current_author : nil
      }
    end

    def update_migration_record(record, version, attributes)
      MigrationGuard::Logger.debug("Tracking migration", version: version, attributes: attributes)
      record.assign_attributes(attributes)
      record.save!
      MigrationGuard::Logger.info("Successfully tracked migration", version: version, status: attributes[:status])
    end
  end
end
