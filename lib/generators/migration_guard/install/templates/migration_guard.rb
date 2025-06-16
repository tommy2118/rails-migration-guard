# frozen_string_literal: true

MigrationGuard.configure do |config|
  # Environments where MigrationGuard is active
  config.enabled_environments = %i[development staging]

  # Git integration level:
  # - :off - No git integration
  # - :warning - Warn about orphaned migrations
  # - :auto_rollback - Automatically suggest rollback
  config.git_integration_level = :warning

  # What information to track for each migration
  config.track_branch = true
  config.track_author = true
  config.track_timestamp = true

  # Behavior options
  config.sandbox_mode = false              # Run migrations in sandbox mode
  config.warn_on_switch = true             # Warn when switching branches
  config.warn_after_migration = true      # Warn about orphaned migrations after running migrations
  config.block_deploy_with_orphans = false # Block deploys with orphaned migrations

  # Cleanup policies
  config.auto_cleanup = false              # Automatically clean up old records
  config.cleanup_after_days = 30           # Days before cleanup

  # Main branch names to check against (in order of preference)
  config.main_branch_names = %w[main master trunk]
  
  # Target branches to compare migrations against
  # When set, migrations will be compared against all specified branches
  # instead of just the main branch. This is useful for teams that use
  # multiple long-lived branches (e.g., develop, staging, production)
  # config.target_branches = %w[main develop staging]
  
  # Logging configuration
  # config.log_level = :info  # :debug, :info, :warn, :error, :fatal
  # config.logger = Rails.logger  # or Logger.new('log/migration_guard.log')
  # config.visible_debug = true   # Show debug output in console/STDOUT
  
  # Enable debug logging via environment variables
  # ENV['MIGRATION_GUARD_DEBUG'] = 'true'     # Enables debug level + visible output
  # ENV['MIGRATION_GUARD_VISIBLE'] = 'true'   # Shows debug output in console
  
  # Examples for different logging scenarios:
  # 
  # 1. Development - visible debug output
  # config.log_level = :debug
  # config.visible_debug = true
  #
  # 2. Production - log to dedicated file  
  # config.logger = MigrationGuard::Logger.file_logger('log/migration_guard.log')
  # config.log_level = :info
  #
  # 3. Troubleshooting - visible output
  # config.logger = MigrationGuard::Logger.visible_logger
end
