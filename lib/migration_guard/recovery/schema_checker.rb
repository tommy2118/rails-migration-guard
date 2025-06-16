# frozen_string_literal: true

module MigrationGuard
  module Recovery
    # Checks for schema-related migration issues
    class SchemaChecker < IssueChecker
      def check
        issues = []
        issues.concat(check_orphaned_in_schema)
        issues.concat(check_missing_from_schema)
        issues
      end

      private

      def check_orphaned_in_schema
        orphaned_versions = schema_versions - tracked_versions
        orphaned_versions.map { |version| build_orphaned_issue(version) }
      end

      def check_missing_from_schema
        applied_records = MigrationGuardRecord.where(status: "applied")
        missing_records = applied_records.reject do |record|
          schema_versions.include?(record.version)
        end

        missing_records.map { |record| build_missing_issue(record) }
      end

      def build_orphaned_issue(version)
        {
          type: :orphaned_schema,
          version: version,
          description: "Schema contains migration not tracked by Migration Guard",
          severity: :medium,
          recovery_options: %i[track_migration remove_from_schema]
        }
      end

      def build_missing_issue(record)
        {
          type: :missing_from_schema,
          version: record.version,
          migration: record,
          description: "Migration tracked as applied but missing from schema",
          severity: :high,
          recovery_options: %i[reapply_migration mark_as_rolled_back]
        }
      end
    end
  end
end
