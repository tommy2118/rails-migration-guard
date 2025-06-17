# frozen_string_literal: true

module MigrationGuard
  module Recovery
    # Checks for partial rollback issues
    class RollbackChecker < IssueChecker
      def check
        find_stuck_rollbacks.map do |record|
          build_issue(record)
        end
      end

      private

      def find_stuck_rollbacks
        timeout = MigrationGuard.configuration.stuck_migration_timeout.minutes.ago
        MigrationGuardRecord.stuck_in_rollback(timeout)
      end

      def build_issue(record)
        {
          type: :partial_rollback,
          version: record.version,
          migration: record,
          description: "Migration appears to be stuck in rollback state",
          severity: :high,
          recovery_options: %i[complete_rollback restore_migration mark_as_rolled_back]
        }
      end
    end
  end
end
