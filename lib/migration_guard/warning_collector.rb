# frozen_string_literal: true

module MigrationGuard
  # Collects warnings during batch migrations for consolidated output
  class WarningCollector
    class << self
      def reset!
        @migration_count = 0
        @warnings_enabled = true
        @batch_start_time = nil
      end

      def start_batch
        @migration_count = 0
        @batch_start_time = Time.current
        @warnings_enabled = MigrationGuard.configuration.warn_after_migration
      end

      def end_batch
        return unless batch_active? && @warnings_enabled

        display_summary if @migration_count.positive?
      ensure
        reset!
      end

      def increment_migration_count
        @migration_count ||= 0
        @migration_count += 1
      end

      def batch_active?
        !@batch_start_time.nil?
      end

      def migration_count
        @migration_count || 0
      end

      def should_show_individual_warnings?
        return true unless batch_active?

        # Show individual warnings only if configured or single migration
        case MigrationGuard.configuration.warning_frequency
        when :once
          false
        when :smart
          # Show warnings immediately for single migrations
          @migration_count <= 1
        else
          # Default to showing each warning (includes :each)
          true
        end
      end

      private

      def display_summary
        reporter = Reporter.new
        orphaned_migrations = reporter.orphaned_migrations

        return if orphaned_migrations.empty?

        output_summary_header
        output_migration_results
        output_orphaned_list(orphaned_migrations)
        output_suggestions
      end

      def output_summary_header
        warn ""
        warn Colorizer.info("=" * 60)
        warn Colorizer.info("⚠️  Migration Guard Summary")
        warn Colorizer.info("=" * 60)
        warn ""
      end

      def output_migration_results
        duration = Time.current - @batch_start_time
        warn Colorizer.success("✅ Successfully ran #{@migration_count} migration(s) in #{duration.round(2)} seconds")
        warn ""
      end

      def output_orphaned_list(orphaned_migrations) # rubocop:disable Metrics/AbcSize
        count = Colorizer.format_migration_count(orphaned_migrations.size, :orphaned)
        plural = orphaned_migrations.size == 1 ? "is" : "are"

        warn Colorizer.warning("⚠️  You have #{count} that #{plural} not in the main branch:")
        warn ""

        # Limit display to first 10 for cleaner output
        display_count = [orphaned_migrations.size, 10].min
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

    # Initialize on load
    reset!
  end
end
