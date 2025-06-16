# frozen_string_literal: true

module MigrationGuard
  class Configuration
    VALID_GIT_INTEGRATION_LEVELS = %i[off warning auto_rollback].freeze
    VALID_LOG_LEVELS = %i[debug info warn error fatal].freeze

    attr_accessor :enabled_environments, :track_branch, :track_author, :track_timestamp, :sandbox_mode,
                  :warn_on_switch, :warn_after_migration, :block_deploy_with_orphans, :auto_cleanup,
                  :main_branch_names, :colorize_output, :target_branches, :logger
    attr_reader :git_integration_level, :cleanup_after_days, :log_level

    def initialize
      set_default_environment_config
      set_default_tracking_config
      set_default_behavior_config
      set_default_git_config
      set_default_logging_config
    end

    private

    def set_default_environment_config
      @enabled_environments = %i[development staging]
    end

    def set_default_tracking_config
      @track_branch = true
      @track_author = true
      @track_timestamp = true
    end

    def set_default_behavior_config
      @sandbox_mode = false
      @warn_on_switch = true
      @warn_after_migration = true
      @block_deploy_with_orphans = false
      @auto_cleanup = false
      @cleanup_after_days = 30
    end

    def set_default_git_config
      @git_integration_level = :warning
      @main_branch_names = %w[main master trunk]
      @target_branches = nil
    end

    def set_default_logging_config
      @colorize_output = true
      @log_level = ENV["MIGRATION_GUARD_DEBUG"] == "true" ? :debug : :info
      @logger = nil # Will default to Rails.logger or Logger.new(STDOUT)
    end

    public

    def git_integration_level=(level)
      unless VALID_GIT_INTEGRATION_LEVELS.include?(level)
        raise ConfigurationError, "Invalid git integration level: #{level}. " \
                                  "Valid options are: #{VALID_GIT_INTEGRATION_LEVELS.join(', ')}"
      end

      @git_integration_level = level
    end

    def cleanup_after_days=(days)
      unless days.is_a?(Integer) && days.positive?
        raise ConfigurationError, "cleanup_after_days must be a positive integer"
      end

      @cleanup_after_days = days
    end

    def log_level=(level)
      unless VALID_LOG_LEVELS.include?(level)
        raise ConfigurationError, "Invalid log level: #{level}. " \
                                  "Valid options are: #{VALID_LOG_LEVELS.join(', ')}"
      end

      @log_level = level
    end

    def to_h # rubocop:disable Metrics/MethodLength
      {
        enabled_environments: enabled_environments,
        git_integration_level: git_integration_level,
        track_branch: track_branch,
        track_author: track_author,
        track_timestamp: track_timestamp,
        sandbox_mode: sandbox_mode,
        warn_on_switch: warn_on_switch,
        warn_after_migration: warn_after_migration,
        block_deploy_with_orphans: block_deploy_with_orphans,
        auto_cleanup: auto_cleanup,
        cleanup_after_days: cleanup_after_days,
        main_branch_names: main_branch_names,
        colorize_output: colorize_output,
        target_branches: target_branches,
        log_level: log_level,
        logger: logger
      }
    end

    def validate
      raise ConfigurationError, "enabled_environments cannot be empty" if enabled_environments.empty?

      raise ConfigurationError, "main_branch_names cannot be empty" if main_branch_names.empty?

      unless VALID_GIT_INTEGRATION_LEVELS.include?(git_integration_level)
        raise ConfigurationError, "Invalid git integration level: #{git_integration_level}"
      end

      true
    end

    def effective_target_branches
      return target_branches if target_branches.present?

      [find_main_branch]
    end

    def find_main_branch
      main_branch_names.each do |branch_name|
        `git rev-parse --verify #{branch_name} >/dev/null 2>&1`
        return branch_name if $CHILD_STATUS.success?
      end

      raise ConfigurationError, "No main branch found. Tried: #{main_branch_names.join(', ')}"
    end
  end
end
