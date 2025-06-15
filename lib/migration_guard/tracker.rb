# frozen_string_literal: true

require_relative "migration_guard_record"

module MigrationGuard
  class Tracker
    def track_migration(version, direction)
      return unless MigrationGuard.enabled?

      case direction
      when :up
        track_up_migration(version)
      when :down
        track_down_migration(version)
      end
    rescue StandardError => e
      Rails.logger.error "[MigrationGuard] Failed to track migration: #{e.message}"
      nil
    end

    def current_branch
      output = `git rev-parse --abbrev-ref HEAD 2>/dev/null`.strip
      output.empty? ? "unknown" : output
    end

    def current_author
      output = `git config user.email 2>/dev/null`.strip
      output.empty? ? "unknown" : output
    end

    def cleanup_old_records
      return unless MigrationGuard.configuration.auto_cleanup

      days_ago = MigrationGuard.configuration.cleanup_after_days
      MigrationGuardRecord
        .where(status: "rolled_back")
        .where("created_at < ?", days_ago.days.ago)
        .destroy_all
    end

    private

    def track_up_migration(version)
      record = MigrationGuardRecord.find_or_initialize_by(version: version)
      
      return if record.persisted? && record.status == "applied"

      record.assign_attributes(
        status: "applied",
        branch: track_branch? ? current_branch : nil,
        author: track_author? ? current_author : nil
      )

      record.save!
      cleanup_old_records
      record
    end

    def track_down_migration(version)
      record = MigrationGuardRecord.find_or_initialize_by(version: version)
      
      record.assign_attributes(
        status: "rolled_back",
        branch: track_branch? ? current_branch : nil,
        author: track_author? ? current_author : nil
      )

      record.save!
      record
    end

    def track_branch?
      MigrationGuard.configuration.track_branch
    end

    def track_author?
      MigrationGuard.configuration.track_author
    end
  end
end