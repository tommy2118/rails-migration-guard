# frozen_string_literal: true

module MigrationGuard
  module Recovery
    # Checks for missing migration files
    class FileChecker < IssueChecker
      def check
        issues = []
        active_migrations.each do |record|
          next if migration_file_exists?(record.version)

          issues << build_issue(record)
        end
        issues
      end

      private

      def active_migrations
        MigrationGuardRecord.where(status: %w[applied rolling_back])
      end

      def build_issue(record)
        {
          type: :missing_file,
          version: record.version,
          migration: record,
          description: "Migration file is missing",
          severity: :critical,
          recovery_options: %i[restore_from_git mark_as_rolled_back mark_as_resolved create_placeholder]
        }
      end
    end
  end
end
