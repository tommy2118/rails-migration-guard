# frozen_string_literal: true

require "logger"
require "active_support"
require "active_record"

require_relative "migration_guard/version"
require_relative "migration_guard/configuration"
require_relative "migration_guard/error"
require_relative "migration_guard/logger"

require_relative "migration_guard/migration_guard_record"
require_relative "migration_guard/tracker"
require_relative "migration_guard/git_integration"
require_relative "migration_guard/reporter"
require_relative "migration_guard/rollbacker"
require_relative "migration_guard/branch_change_detector"
require_relative "migration_guard/post_migration_checker"
require_relative "migration_guard/diagnostic_runner"
require_relative "migration_guard/rake_tasks"

require_relative "migration_guard/railtie" if defined?(Rails::Railtie)

module MigrationGuard
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      MigrationGuard::Logger.debug("Configuring MigrationGuard")
      yield(configuration)
      MigrationGuard::Logger.debug("MigrationGuard configured",
                                   enabled_environments: configuration.enabled_environments,
                                   log_level: configuration.log_level)
    end

    def enabled?
      if Rails.env.production?
        MigrationGuard::Logger.debug("MigrationGuard disabled in production")
        return false
      end

      enabled = configuration.enabled_environments.include?(Rails.env.to_sym)
      MigrationGuard::Logger.debug("MigrationGuard enabled check",
                                   environment: Rails.env,
                                   enabled: enabled)
      enabled
    end

    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end
