# frozen_string_literal: true

module MigrationGuard
  module Recovery
    # Checks for version conflicts and duplicates
    class VersionConflictChecker < IssueChecker
      def check
        find_duplicate_versions.map do |version, count|
          build_issue(version, count)
        end
      end

      private

      def find_duplicate_versions
        MigrationGuardRecord
          .group(:version)
          .count
          .select { |_, count| count > 1 }
      end

      def build_issue(version, count)
        records = MigrationGuardRecord.where(version: version)
        {
          type: :version_conflict,
          version: version,
          migrations: records,
          description: "Version conflict: Multiple records exist for the same migration version (#{count} records)",
          severity: :critical,
          recovery_options: %i[consolidate_records remove_duplicates]
        }
      end
    end
  end
end
