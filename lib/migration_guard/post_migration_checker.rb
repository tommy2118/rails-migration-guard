# frozen_string_literal: true

require_relative "colorizer"

module MigrationGuard
  class PostMigrationChecker
    def initialize
      @reporter = Reporter.new
      @configuration = MigrationGuard.configuration
    end

    def check_and_warn
      return unless should_check?

      orphaned_migrations = @reporter.orphaned_migrations
      return if orphaned_migrations.empty?

      output_warning(orphaned_migrations)
    end

    private

    def should_check?
      @configuration.warn_after_migration && MigrationGuard.enabled?
    end

    def output_warning(orphaned_migrations)
      warn ""
      warn Colorizer.warning("⚠️  Migration Guard Warning")
      warn Colorizer.warning("=" * 50)
      warn ""
      warn "You have #{Colorizer.format_migration_count(orphaned_migrations.size, :orphaned)} " \
           "that #{orphaned_migrations.size == 1 ? 'is' : 'are'} not in the main branch:"
      warn ""

      orphaned_migrations.each do |migration|
        warn "  • #{Colorizer.bold(migration[:version])} - #{migration[:branch]}"
      end

      warn ""
      warn "#{Colorizer.info('Suggestions:')}"
      warn "  1. Commit these migrations to your branch before merging"
      warn "  2. Run #{Colorizer.info('rails db:migration:rollback_orphaned')} to remove them"
      warn "  3. Run #{Colorizer.info('rails db:migration:status')} for more details"
      warn ""
    end
  end
end