# frozen_string_literal: true

require "rails/railtie"

module MigrationGuard
  class Railtie < Rails::Railtie
    railtie_name :migration_guard

    # Load rake tasks
    rake_tasks do
      path = File.expand_path("../tasks", __dir__)
      Dir.glob("#{path}/*.rake").each { |f| load f }
    end

    # Load generators
    generators do
      require_relative "../generators/migration_guard/install/install_generator"
    end

    # Initialize MigrationGuard after Rails has loaded
    config.after_initialize do
      if MigrationGuard.enabled?
        # Hook into ActiveRecord::Migration
        ActiveSupport.on_load(:active_record) do
          require_relative "migration_extension"
        end

        # Setup the MigrationGuardRecord model
        MigrationGuardRecord.setup_serialization if defined?(MigrationGuardRecord)
      end
    end

    # Console helpers
    console do
      if MigrationGuard.enabled?
        Rails.logger.debug { "MigrationGuard is enabled in #{Rails.env}" }
        reporter = MigrationGuard::Reporter.new
        Rails.logger.debug reporter.summary_line
      end
    end

    # Add configuration options to Rails
    config.migration_guard = ActiveSupport::OrderedOptions.new

    initializer "migration_guard.check_git_hooks" do
      if MigrationGuard.enabled? && MigrationGuard.configuration.warn_on_switch
        # Check if git hooks are installed
        git_hooks_path = Rails.root.join(".git/hooks/post-checkout")
        unless git_hooks_path.exist?
          msg = "[MigrationGuard] Git hooks not installed. Run 'rails generate migration_guard:hooks' to install."
          Rails.logger.info msg
        end
      end
    end
  end
end
