# frozen_string_literal: true

require_relative "../check_printer"

module MigrationGuard
  module Diagnostics
    # Checks database connection, migration guard tables,
    # environment configuration, and sandbox mode
    class InfrastructureChecker
      include CheckPrinter

      def initialize(issues:, warnings:, output:)
        @issues = issues
        @warnings = warnings
        @output = output
      end

      def run_checks
        check_database_connection
        check_migration_guard_tables
        check_environment_configuration
        check_sandbox_mode
      end

      private

      def check_database_connection
        ActiveRecord::Base.connection.execute("SELECT 1")
        print_check("Database connection", :success)
      rescue StandardError => e
        @issues << ["Database connection failed", "Check your database configuration: #{e.message}"]
        print_check("Database connection", :error)
      end

      def check_migration_guard_tables
        MigrationGuard::MigrationGuardRecord.table_exists?
        count = MigrationGuard::MigrationGuardRecord.count
        print_check("Migration guard tables", :success, "#{count} records")
      rescue StandardError
        @issues << ["Migration guard tables missing",
                    "Run 'rails generate migration_guard:install' and 'rails db:migrate'"]
        print_check("Migration guard tables", :error)
      end

      # rubocop:disable Metrics/MethodLength
      def check_environment_configuration
        config = MigrationGuard.configuration

        if defined?(Rails) && Rails.respond_to?(:env)
          current_env = Rails.env.to_sym

          if config.enabled_environments.include?(current_env)
            envs = config.enabled_environments.join(", ")
            print_check("Environment configuration", :success, "enabled in: #{envs}")
          else
            @warnings << ["MigrationGuard disabled in current environment",
                          "Current: #{current_env}, Enabled in: #{config.enabled_environments.join(', ')}"]
            print_check("Environment configuration", :warning, "disabled in #{current_env}")
          end
        else
          @warnings << ["Rails environment not detected",
                        "MigrationGuard is designed to work within a Rails application environment"]
          print_check("Environment configuration", :warning, "Rails not loaded")
        end
      end
      # rubocop:enable Metrics/MethodLength

      def check_sandbox_mode
        config = MigrationGuard.configuration

        if config.sandbox_mode
          @warnings << ["Sandbox mode is enabled",
                        "Migrations will be rolled back after execution. Disable sandbox_mode for real changes"]
          print_check("Sandbox mode", :warning, "ACTIVE (changes will be rolled back)")
        else
          print_check("Sandbox mode", :success, "disabled")
        end
      end

      def puts(*args)
        @output.send(:puts, *args)
      end
    end
  end
end
