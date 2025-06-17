# frozen_string_literal: true

module MigrationGuard
  # Constants for sandbox mode messages
  module SandboxMessages
    START = "🧪 SANDBOX MODE ACTIVE - Database changes will be rolled back"
    COMPLETE = "⚠️  SANDBOX: Database changes rolled back. Schema.rb updated for inspection."
  end

  module MigrationExtension
    def self.prepended(base)
      base.singleton_class.prepend(ClassMethods)
    end

    module ClassMethods
      def migrate(direction)
        # Track in class method only if we have version
        if MigrationGuard.enabled? && respond_to?(:version) && direction == :up
          MigrationGuard::WarningCollector.increment_migration_count
        end

        super
      end
    end

    def migrate(direction)
      result = super

      if MigrationGuard.enabled? && respond_to?(:version)
        tracker = MigrationGuard::Tracker.new
        tracker.track_migration(version.to_s, direction)

        # Check for orphaned migrations after running up migrations
        if direction == :up && MigrationGuard::WarningCollector.should_show_individual_warnings?
          checker = MigrationGuard::PostMigrationChecker.new
          checker.check_and_warn
          MigrationGuard::WarningCollector.mark_warnings_shown
        end
      end

      result
    end

    def exec_migration(conn, direction)
      if MigrationGuard.enabled? && MigrationGuard.configuration.sandbox_mode && direction == :up
        display_sandbox_start_message
        Rails.logger&.debug { "[MigrationGuard] Running migration #{version} in sandbox mode..." }
        conn.transaction(requires_new: true) do
          super
          Rails.logger&.debug "[MigrationGuard] Migration would succeed. Rolling back sandbox..."
          raise ActiveRecord::Rollback
        end
        display_sandbox_complete_message
        Rails.logger&.debug "[MigrationGuard] Sandbox rollback complete. Run without sandbox to apply."
      else
        super
      end
    end

    private

    def display_sandbox_start_message
      return unless should_display_sandbox_messages?

      display_sandbox_message(SandboxMessages::START, :info)
    end

    def display_sandbox_complete_message
      return unless should_display_sandbox_messages?

      display_sandbox_message(SandboxMessages::COMPLETE, :warn)
    end

    def display_sandbox_message(message, logger_level)
      require_relative "colorizer"

      # Map logger levels to colorizer methods
      colorizer_method = logger_level == :warn ? :warning : logger_level

      if Rails.logger
        Rails.logger.public_send(logger_level, MigrationGuard::Colorizer.public_send(colorizer_method, message))
      else
        puts MigrationGuard::Colorizer.public_send(colorizer_method, message) # rubocop:disable Rails/Output
      end
    end

    def should_display_sandbox_messages?
      # Respect explicit quiet flag (supports multiple true values)
      return false if env_var_truthy?("MIGRATION_GUARD_SANDBOX_QUIET")

      # Show in test only if explicitly verbose
      return false if Rails.env.test? && !env_var_truthy?("MIGRATION_GUARD_SANDBOX_VERBOSE")

      true
    end

    def env_var_truthy?(env_var_name)
      value = ENV[env_var_name]&.downcase
      %w[true 1 yes].include?(value)
    end
  end
end

# Prepend the extension to ActiveRecord::Migration
ActiveSupport.on_load(:active_record) do
  ActiveRecord::Migration.prepend(MigrationGuard::MigrationExtension)
end
