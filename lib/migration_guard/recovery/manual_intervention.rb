# frozen_string_literal: true

module MigrationGuard
  module Recovery
    # Handles manual intervention instructions
    class ManualIntervention
      def show?(issue)
        show_header
        show_sql_commands(issue)
        show_footer(issue)
        true
      end

      private

      def show_header
        Rails.logger.debug { "\n#{Colorizer.info('Manual intervention SQL commands:')}" }
        Rails.logger.debug Colorizer.warning("⚠️  Review these commands carefully before executing")
        Rails.logger.debug ""
      end

      def show_footer(issue)
        Rails.logger.debug ""
        Rails.logger.debug "After manual intervention, update the tracking record:"
        Rails.logger.debug update_command(issue[:version])
        Rails.logger.debug ""
      end

      def update_command(version)
        "MigrationGuardRecord.find_by(version: '#{version}').update!(status: 'resolved')"
      end

      def show_sql_commands(issue)
        case issue[:type]
        when :partial_rollback
          show_partial_rollback_sql(issue)
        when :orphaned_schema
          show_orphaned_schema_sql(issue)
        when :missing_from_schema
          show_missing_from_schema_sql(issue)
        when :missing_file
          show_missing_file_sql(issue)
        when :version_conflict
          show_version_conflict_sql(issue)
        end
      end

      def show_partial_rollback_sql(issue)
        version = issue[:version]
        show_rollback_commands(version)
        Rails.logger.debug ""
        show_restore_commands(version)
      end

      def show_rollback_commands(version)
        Rails.logger.debug "-- To complete the rollback:"
        Rails.logger.debug deletion_sql(version)
        Rails.logger.debug update_status_sql(version, "rolled_back")
      end

      def show_restore_commands(version)
        Rails.logger.debug "-- To restore the migration:"
        Rails.logger.debug insertion_sql(version)
        Rails.logger.debug update_status_sql(version, "applied")
      end

      def show_orphaned_schema_sql(issue)
        version = issue[:version]
        Rails.logger.debug "-- To track this migration:"
        Rails.logger.debug tracking_insert_sql(version)
        Rails.logger.debug ""
        Rails.logger.debug "-- To remove from schema:"
        Rails.logger.debug deletion_sql(version)
      end

      def show_missing_from_schema_sql(issue)
        version = issue[:version]
        Rails.logger.debug "-- To add to schema:"
        Rails.logger.debug insertion_sql(version)
        Rails.logger.debug ""
        Rails.logger.debug "-- To mark as rolled back:"
        Rails.logger.debug update_status_sql(version, "rolled_back")
      end

      def show_missing_file_sql(issue)
        version = issue[:version]
        Rails.logger.debug "-- Migration file is missing. Options:"
        Rails.logger.debug ""
        show_git_restore_option(version)
        Rails.logger.debug ""
        show_mark_resolved_option(version)
      end

      def show_git_restore_option(version)
        Rails.logger.debug "-- 1. Restore from git:"
        Rails.logger.debug git_restore_commands(version)
      end

      def show_mark_resolved_option(version)
        Rails.logger.debug "-- 2. Mark as resolved:"
        Rails.logger.debug mark_as_resolved_sql(version)
      end

      def show_version_conflict_sql(issue)
        version = issue[:version]
        count = issue[:migrations].count
        Rails.logger.debug { "-- Found #{count} records for version #{version}" }
        Rails.logger.debug "-- Keep the most recent and delete others:"
        Rails.logger.debug ""
        Rails.logger.debug version_conflict_deletion_sql(version)
      end

      def deletion_sql(version)
        "DELETE FROM schema_migrations WHERE version = '#{version}';"
      end

      def insertion_sql(version)
        "INSERT INTO schema_migrations (version) VALUES ('#{version}');"
      end

      def update_status_sql(version, status)
        "UPDATE migration_guard_records SET status = '#{status}' WHERE version = '#{version}';"
      end

      def tracking_insert_sql(version)
        [
          "INSERT INTO migration_guard_records (version, status, branch, created_at, updated_at)",
          "VALUES ('#{version}', 'applied', 'unknown', NOW(), NOW());"
        ].join("\n")
      end

      def git_restore_commands(version)
        [
          "git log --all --full-history -- 'db/migrate/#{version}_*.rb'",
          "git show COMMIT_HASH:db/migrate/#{version}_*.rb > db/migrate/#{version}_restored.rb"
        ].join("\n")
      end

      def mark_as_resolved_sql(version)
        [
          "UPDATE migration_guard_records SET status = 'resolved', metadata = ",
          "  JSON_SET(metadata, '$.missing_file', 'true') WHERE version = '#{version}';"
        ].join("\n")
      end

      def version_conflict_deletion_sql(version)
        [
          "DELETE FROM migration_guard_records",
          "WHERE version = '#{version}'",
          "  AND id NOT IN (",
          "    SELECT id FROM (",
          "      SELECT id FROM migration_guard_records",
          "      WHERE version = '#{version}'",
          "      ORDER BY updated_at DESC",
          "      LIMIT 1",
          "    ) AS keeper",
          "  );"
        ].join("\n")
      end
    end
  end
end
