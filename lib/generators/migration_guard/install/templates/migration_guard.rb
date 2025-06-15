# frozen_string_literal: true

MigrationGuard.configure do |config|
  # Environments where MigrationGuard is active
  config.enabled_environments = [:development, :staging]

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
  config.block_deploy_with_orphans = false # Block deploys with orphaned migrations

  # Cleanup policies
  config.auto_cleanup = false              # Automatically clean up old records
  config.cleanup_after_days = 30           # Days before cleanup

  # Main branch names to check against (in order of preference)
  config.main_branch_names = %w[main master trunk]
end