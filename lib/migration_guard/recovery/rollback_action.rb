# frozen_string_literal: true

module MigrationGuard
  module Recovery
    # Handles rollback-related recovery actions
    class RollbackAction < BaseAction
      def complete_rollback(issue)
        migration = issue[:migration]
        log_info("Completing rollback for #{migration.version}...")

        remove_from_schema_if_exists(migration.version)
        update_rollback_status(migration)
        log_success("✓ Rollback completed for #{migration.version}")
        true
      rescue StandardError => e
        log_error("✗ Failed to complete rollback: #{e.message}")
        false
      end

      def mark_as_rolled_back(issue) # rubocop:disable Naming/PredicateMethod
        migration = issue[:migration]
        log_info("Marking #{migration.version} as rolled back...")

        update_migration_metadata(
          migration,
          "marked_as_rolled_back",
          "warning" => "Status updated without verifying actual rollback"
        )
        migration.update!(status: "rolled_back")

        log_success("✓ Marked as rolled back: #{migration.version}")
        true
      end

      private

      def remove_from_schema_if_exists(version)
        return unless migration_exists_in_schema?(version)

        ActiveRecord::Base.connection.execute(
          ActiveRecord::Base.sanitize_sql(
            ["DELETE FROM schema_migrations WHERE version = ?", version]
          )
        )
      end

      def update_rollback_status(migration)
        update_migration_metadata(migration, "complete_rollback")
        migration.update!(status: "rolled_back")
      end
    end
  end
end
