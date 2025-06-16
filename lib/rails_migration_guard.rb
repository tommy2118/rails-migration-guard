# frozen_string_literal: true

require "logger"
require "active_support"
require "active_record"

require_relative "migration_guard/version"
require_relative "migration_guard/configuration"
require_relative "migration_guard/error"

require_relative "migration_guard/migration_guard_record"
require_relative "migration_guard/tracker"
require_relative "migration_guard/git_integration"
require_relative "migration_guard/reporter"
require_relative "migration_guard/rollbacker"
require_relative "migration_guard/branch_change_detector"
require_relative "migration_guard/rake_tasks"

require_relative "migration_guard/railtie" if defined?(Rails::Railtie)

module MigrationGuard
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def enabled?
      return false if Rails.env.production?

      configuration.enabled_environments.include?(Rails.env.to_sym)
    end

    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end
