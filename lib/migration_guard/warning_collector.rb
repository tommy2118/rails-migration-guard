# frozen_string_literal: true

require_relative "warning_display"

module MigrationGuard
  # Collects warnings during batch migrations for consolidated output
  class WarningCollector
    class << self
      def reset!
        Thread.current[:migration_guard_migration_count] = 0
        Thread.current[:migration_guard_warnings_enabled] = true
        Thread.current[:migration_guard_batch_start_time] = nil
        Thread.current[:migration_guard_warnings_shown] = false
      end

      def start_batch
        Thread.current[:migration_guard_migration_count] = 0
        Thread.current[:migration_guard_batch_start_time] = Time.current
        Thread.current[:migration_guard_warnings_enabled] = MigrationGuard.configuration.warn_after_migration
        Thread.current[:migration_guard_warnings_shown] = false
      end

      def end_batch
        return unless batch_active?
        return unless warnings_enabled?

        display_summary if should_display_summary?
      ensure
        reset!
      end

      private

      def should_display_summary?
        return false unless migration_count.positive?

        case MigrationGuard.configuration.warning_frequency
        when :once, :summary
          true
        when :smart
          # In smart mode, show summary if we have multiple migrations
          # or if we haven't shown warnings yet
          migration_count > 1 || !warnings_already_shown?
        else
          false # :each mode doesn't show summary
        end
      end

      public

      def increment_migration_count
        Thread.current[:migration_guard_migration_count] ||= 0
        Thread.current[:migration_guard_migration_count] += 1
      end

      def batch_active?
        !Thread.current[:migration_guard_batch_start_time].nil?
      end

      def migration_count
        Thread.current[:migration_guard_migration_count] || 0
      end

      def mark_warnings_shown
        Thread.current[:migration_guard_warnings_shown] = true
      end

      def warnings_already_shown?
        Thread.current[:migration_guard_warnings_shown] == true
      end

      private

      def warnings_enabled?
        Thread.current[:migration_guard_warnings_enabled] != false
      end

      def batch_start_time
        Thread.current[:migration_guard_batch_start_time]
      end

      public

      def should_show_individual_warnings?
        return true unless batch_active?

        # Show individual warnings only if configured
        case MigrationGuard.configuration.warning_frequency
        when :once, :summary
          false
        when :smart
          # In smart mode: show warnings for first migration only
          # After that, consolidate into summary
          if warnings_already_shown?
            false
          else
            # Show warnings immediately for single migrations
            migration_count <= 1
          end
        else
          # Default to showing each warning (includes :each)
          true
        end
      end

      def display_summary
        reporter = Reporter.new
        orphaned_migrations = reporter.orphaned_migrations

        WarningDisplay.display_summary(migration_count, batch_start_time, orphaned_migrations)
      end
    end

    # Initialize on load
    reset!
  end
end
