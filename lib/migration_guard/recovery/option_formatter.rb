# frozen_string_literal: true

module MigrationGuard
  module Recovery
    # Formats recovery options for display
    class OptionFormatter
      OPTION_DESCRIPTIONS = {
        complete_rollback: "Complete the rollback (remove remaining schema/data changes)",
        restore_migration: "Restore migration (re-apply schema changes)",
        mark_as_rolled_back: "Mark as rolled back (update status only)",
        track_migration: "Track this migration in Migration Guard",
        remove_from_schema: "Remove from schema_migrations table",
        reapply_migration: "Re-apply the migration",
        restore_from_git: "Restore migration file from git history",
        consolidate_records: "Consolidate duplicate records into one",
        remove_duplicates: "Remove duplicate tracking records"
      }.freeze

      def self.format(option)
        OPTION_DESCRIPTIONS[option] || option.to_s.humanize
      end
    end
  end
end
