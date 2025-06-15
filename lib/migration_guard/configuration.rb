# frozen_string_literal: true

module MigrationGuard
  class Configuration
    VALID_GIT_INTEGRATION_LEVELS = %i[off warning auto_rollback].freeze

    attr_accessor :enabled_environments, :track_branch, :track_author, :track_timestamp,
                  :sandbox_mode, :warn_on_switch, :block_deploy_with_orphans,
                  :auto_cleanup, :main_branch_names
    
    attr_writer :cleanup_after_days

    attr_reader :git_integration_level

    def initialize
      @enabled_environments = [:development, :staging]
      @git_integration_level = :warning
      @track_branch = true
      @track_author = true
      @track_timestamp = true
      @sandbox_mode = false
      @warn_on_switch = true
      @block_deploy_with_orphans = false
      @auto_cleanup = false
      @cleanup_after_days = 30
      @main_branch_names = %w[main master trunk]
    end

    def git_integration_level=(level)
      unless VALID_GIT_INTEGRATION_LEVELS.include?(level)
        raise ConfigurationError, "Invalid git integration level: #{level}. " \
                                  "Valid options are: #{VALID_GIT_INTEGRATION_LEVELS.join(', ')}"
      end

      @git_integration_level = level
    end
    
    def cleanup_after_days
      @cleanup_after_days
    end

    def cleanup_after_days=(days)
      unless days.is_a?(Integer) && days.positive?
        raise ConfigurationError, "cleanup_after_days must be a positive integer"
      end

      @cleanup_after_days = days
    end

    def to_h
      {
        enabled_environments: enabled_environments,
        git_integration_level: git_integration_level,
        track_branch: track_branch,
        track_author: track_author,
        track_timestamp: track_timestamp,
        sandbox_mode: sandbox_mode,
        warn_on_switch: warn_on_switch,
        block_deploy_with_orphans: block_deploy_with_orphans,
        auto_cleanup: auto_cleanup,
        cleanup_after_days: cleanup_after_days,
        main_branch_names: main_branch_names
      }
    end

    def validate!
      if enabled_environments.empty?
        raise ConfigurationError, "enabled_environments cannot be empty"
      end

      if main_branch_names.empty?
        raise ConfigurationError, "main_branch_names cannot be empty"
      end

      unless VALID_GIT_INTEGRATION_LEVELS.include?(git_integration_level)
        raise ConfigurationError, "Invalid git integration level: #{git_integration_level}"
      end

      true
    end
  end
end