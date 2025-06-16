# frozen_string_literal: true

require_relative "colorizer"

module MigrationGuard
  class PostMigrationChecker
    def initialize
      @reporter = Reporter.new
      @configuration = MigrationGuard.configuration
      MigrationGuard::Logger.debug("Initialized PostMigrationChecker")
    end

    def check_and_warn
      MigrationGuard::Logger.debug("Checking for post-migration warnings")

      unless should_check?
        MigrationGuard::Logger.debug("Post-migration warnings disabled or not enabled")
        return
      end

      orphaned_migrations = @reporter.orphaned_migrations
      if orphaned_migrations.empty?
        MigrationGuard::Logger.debug("No orphaned migrations found for post-migration check")
        return
      end

      MigrationGuard::Logger.warn("Displaying post-migration warnings", count: orphaned_migrations.size)
      output_warning(orphaned_migrations)
    end

    private

    def should_check?
      @configuration.warn_after_migration && MigrationGuard.enabled?
    end

    def output_warning(orphaned_migrations)
      output_header
      output_migration_list(orphaned_migrations)
      output_suggestions
    end

    def output_header
      warn ""
      warn Colorizer.warning("⚠️  Migration Guard Warning")
      warn Colorizer.warning("=" * 50)
      warn ""
    end

    def output_migration_list(orphaned_migrations)
      count = Colorizer.format_migration_count(orphaned_migrations.size, :orphaned)
      plural = orphaned_migrations.size == 1 ? "is" : "are"
      warn "You have #{count} that #{plural} not in the main branch:"
      warn ""

      orphaned_migrations.each do |migration|
        warn "  • #{Colorizer.bold(migration[:version])} - #{migration[:branch]}"
      end
    end

    def output_suggestions
      warn ""
      warn Colorizer.info("Suggestions:")
      warn "  1. Commit these migrations to your branch before merging"
      warn "  2. Run #{Colorizer.info('rails db:migration:rollback_orphaned')} to remove them"
      warn "  3. Run #{Colorizer.info('rails db:migration:status')} for more details"
      warn ""
    end
  end
end
