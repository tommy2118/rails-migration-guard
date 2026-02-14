# frozen_string_literal: true

require_relative "migration_guard_record"
require_relative "git_integration"

module MigrationGuard
  class Tracker
    def initialize(git_integration: GitIntegration.new)
      @git_integration = git_integration
    end

    def track_migration(version, direction, execution_time: nil)
      return unless MigrationGuard.enabled?

      MigrationGuard::Logger.debug("Starting migration tracking", version: version, direction: direction)

      case direction
      when :up
        track_up_migration(version, execution_time)
      when :down
        track_down_migration(version, execution_time)
      end
    rescue StandardError => e
      MigrationGuard::Logger.error("Failed to track migration", error: e.message, version: version)
      nil
    end

    def current_branch
      branch = @git_integration.current_branch
      MigrationGuard::Logger.debug("Current branch detected", branch: branch)
      branch
    rescue GitError
      MigrationGuard::Logger.debug("Current branch detected", branch: "unknown")
      "unknown"
    end

    def current_author
      author = @git_integration.current_author || "unknown"
      MigrationGuard::Logger.debug("Current author detected", author: author)
      author
    end

    def cleanup_old_records
      return unless MigrationGuard.configuration.auto_cleanup

      days_ago = MigrationGuard.configuration.cleanup_after_days
      MigrationGuard::Logger.debug("Starting cleanup of old records", days_ago: days_ago)

      count = MigrationGuardRecord
              .where(status: MigrationGuardRecord::STATUS_ROLLED_BACK)
              .where(created_at: ...days_ago.days.ago)
              .destroy_all
              .size

      MigrationGuard::Logger.info("Cleaned up old migration records", count: count) if count.positive?
    end

    private

    def track_up_migration(version, execution_time = nil)
      record = MigrationGuardRecord.find_or_initialize_by(version: version)

      if record.persisted? && record.status == MigrationGuardRecord::STATUS_APPLIED
        MigrationGuard::Logger.debug("Migration already tracked as applied", version: version)
        return
      end

      attributes = build_migration_attributes(MigrationGuardRecord::STATUS_APPLIED, "UP", execution_time)
      update_migration_record(record, version, attributes)
      cleanup_old_records
      record
    end

    def track_down_migration(version, execution_time = nil)
      record = MigrationGuardRecord.find_or_initialize_by(version: version)
      attributes = build_migration_attributes(MigrationGuardRecord::STATUS_ROLLED_BACK, "DOWN", execution_time)
      update_migration_record(record, version, attributes)
      record
    end

    def track_branch?
      MigrationGuard.configuration.track_branch
    end

    def track_author?
      MigrationGuard.configuration.track_author
    end

    def build_migration_attributes(status, direction = nil, execution_time = nil)
      metadata = {}
      metadata["direction"] = direction if direction
      metadata["execution_time"] = execution_time if execution_time
      metadata["tracked_at"] = Time.current.iso8601

      {
        status: status,
        branch: track_branch? ? current_branch : nil,
        author: track_author? ? current_author : nil,
        metadata: metadata.any? ? metadata : nil
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
