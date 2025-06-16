# frozen_string_literal: true

module MigrationGuard
  module Recovery
    # Checks for partial rollback issues
    class RollbackChecker < IssueChecker
      ROLLBACK_TIMEOUT = 1.hour

      def check
        find_stuck_rollbacks.map do |record|
          build_issue(record)
        end
      end

      private

      def find_stuck_rollbacks
        MigrationGuardRecord
          .where(status: "rolling_back")
          .where(updated_at: ...ROLLBACK_TIMEOUT.ago)
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
