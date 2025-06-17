# frozen_string_literal: true

module MigrationGuard
  class MigrationGuardRecord < ActiveRecord::Base
    self.table_name = "migration_guard_records"

    validates :version, presence: true, uniqueness: true
    validates :status, presence: true

    scope :orphaned, -> { where(status: "orphaned") }
    scope :recent, -> { where("created_at > ?", 7.days.ago) }
    scope :for_branch, ->(branch) { where(branch: branch) }
    scope :for_author, ->(author) { where("author LIKE ?", "%#{author}%") }
    scope :applied, -> { where(status: "applied") }
    scope :rolled_back, -> { where(status: "rolled_back") }
    scope :history_ordered, -> { order(created_at: :desc) }
    scope :for_version, ->(version) { where(version: version) }
    scope :within_days, ->(days) { where("created_at > ?", days.days.ago) }
    scope :stuck_in_rollback, ->(timeout) { where(status: "rolling_back").where(updated_at: ..timeout) }

    def self.setup_serialization
      serialize :metadata, JSON if connection_pool.connected? && !connection.adapter_name.match?(/PostgreSQL|MySQL/)
    rescue ActiveRecord::ConnectionNotEstablished
      # Connection not established yet, will set up serialization later
    end

    def orphaned?
      status == "orphaned"
    end

    def rolled_back?
      status == "rolled_back"
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
      when "applied" then "✓ Applied"
      when "rolled_back" then "⤺ Rolled Back"
      when "orphaned" then "⚠ Orphaned"
      when "synced" then "✓ Synced"
      else status.humanize
      end
    end
  end
end
