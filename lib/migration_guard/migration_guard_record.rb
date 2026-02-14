# frozen_string_literal: true

module MigrationGuard
  class MigrationGuardRecord < ActiveRecord::Base
    self.table_name = "migration_guard_records"

    STATUS_APPLIED = "applied"
    STATUS_ROLLED_BACK = "rolled_back"
    STATUS_ORPHANED = "orphaned"
    STATUS_SYNCED = "synced"
    STATUS_ROLLING_BACK = "rolling_back"

    STATUSES = [STATUS_APPLIED, STATUS_ROLLED_BACK, STATUS_ORPHANED, STATUS_SYNCED, STATUS_ROLLING_BACK].freeze

    validates :version, presence: true, uniqueness: true
    validates :status, presence: true, inclusion: { in: STATUSES }

    scope :orphaned, -> { where(status: STATUS_ORPHANED) }
    scope :recent, -> { where("created_at > ?", 7.days.ago) }
    scope :for_branch, ->(branch) { where(branch: branch) }
    scope :for_author, ->(author) { where("author LIKE ?", "%#{author}%") }
    scope :applied, -> { where(status: STATUS_APPLIED) }
    scope :rolled_back, -> { where(status: STATUS_ROLLED_BACK) }
    scope :history_ordered, -> { order(created_at: :desc) }
    scope :for_version, ->(version) { where(version: version) }
    scope :within_days, ->(days) { where("created_at > ?", days.days.ago) }
    scope :stuck_in_rollback, ->(timeout) { where(status: STATUS_ROLLING_BACK).where(updated_at: ..timeout) }

    def self.setup_serialization
      serialize :metadata, JSON if connection_pool.connected? && !connection.adapter_name.match?(/PostgreSQL|MySQL/)
    rescue ActiveRecord::ConnectionNotEstablished
      # Connection not established yet, will set up serialization later
    end

    def orphaned?
      status == STATUS_ORPHANED
    end

    def rolled_back?
      status == STATUS_ROLLED_BACK
    end

    def add_metadata(key, value)
      self.metadata ||= {}
      self.metadata[key] = value
      save!
    end

    def migration_file_name
      return nil unless version

      # Try to find the actual migration file
      migration_pattern = "#{version}_*.rb"

      # Use Rails.root if available, otherwise current directory
      root_path = defined?(Rails) && Rails.root ? Rails.root : Dir.pwd
      migration_files = Dir.glob(File.join(root_path, "db", "migrate", migration_pattern))
      return File.basename(migration_files.first, ".rb") if migration_files.any?

      # Fallback to version if file not found
      version
    end

    def direction
      metadata&.dig("direction") || (rolled_back? ? "DOWN" : "UP")
    end

    def execution_time
      return nil unless metadata&.dig("execution_time")

      "#{metadata['execution_time']}s"
    end

    def display_status
      case status
      when STATUS_APPLIED then "✓ Applied"
      when STATUS_ROLLED_BACK then "⤺ Rolled Back"
      when STATUS_ORPHANED then "⚠ Orphaned"
      when STATUS_SYNCED then "✓ Synced"
      else status.humanize
      end
    end
  end
end
