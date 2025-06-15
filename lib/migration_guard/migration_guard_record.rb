# frozen_string_literal: true

module MigrationGuard
  class MigrationGuardRecord < ApplicationRecord
    self.table_name = "migration_guard_records"

    validates :version, presence: true, uniqueness: true
    validates :status, presence: true

    scope :orphaned, -> { where(status: "orphaned") }
    scope :recent, -> { where("created_at > ?", 7.days.ago) }
    scope :for_branch, ->(branch) { where(branch: branch) }
    scope :applied, -> { where(status: "applied") }
    scope :rolled_back, -> { where(status: "rolled_back") }

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
  end
end
