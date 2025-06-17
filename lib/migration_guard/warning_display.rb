# frozen_string_literal: true

module MigrationGuard
  # Handles the display formatting for warning messages
  module WarningDisplay
    class << self
      def display_summary(migration_count, batch_start_time, orphaned_migrations)
        return if orphaned_migrations.empty?

        output_summary_header
        output_migration_results(migration_count, batch_start_time)
        output_orphaned_list(orphaned_migrations)
        output_suggestions
      end

      private

      def output_summary_header
        warn ""
        warn Colorizer.info("=" * 60)
        warn Colorizer.info("⚠️  Migration Guard Summary")
        warn Colorizer.info("=" * 60)
        warn ""
      end

      def output_migration_results(migration_count, batch_start_time)
        duration = Time.current - batch_start_time
        warn Colorizer.success("✅ Successfully ran #{migration_count} migration(s) in #{duration.round(2)} seconds")
        warn ""
      end

      def output_orphaned_list(orphaned_migrations)
        count = Colorizer.format_migration_count(orphaned_migrations.size, :orphaned)
        plural = orphaned_migrations.size == 1 ? "is" : "are"

        warn Colorizer.warning("⚠️  You have #{count} that #{plural} not in the main branch:")
        warn ""

        display_migrations(orphaned_migrations)
      end

      def display_migrations(orphaned_migrations)
        max_display = MigrationGuard.configuration.max_warnings_display
        display_count = [orphaned_migrations.size, max_display].min

        orphaned_migrations.first(display_count).each do |migration|
          warn "  • #{Colorizer.bold(migration[:version])} - #{migration[:branch]}"
        end

        return unless orphaned_migrations.size > display_count

        warn "  • ... and #{orphaned_migrations.size - display_count} more"
      end

      def output_suggestions
        warn ""
        warn Colorizer.info("Suggestions:")
        warn "  1. Commit these migrations to your branch before merging"
        warn "  2. Run #{Colorizer.info('rails db:migration:rollback_orphaned')} to remove them"
        warn "  3. Run #{Colorizer.info('rails db:migration:status')} for more details"
        warn ""
      end

      def warn(message)
        Rails.logger&.warn(message)
        Kernel.warn(message)
      end
    end
  end
end
