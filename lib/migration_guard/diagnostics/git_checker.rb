# frozen_string_literal: true

require_relative "../check_printer"

module MigrationGuard
  module Diagnostics
    # Checks git repository, branch detection, and target branch configuration
    class GitChecker
      include CheckPrinter

      def initialize(issues:, warnings:, output:, git_integration:)
        @issues = issues
        @warnings = warnings
        @output = output
        @git_integration = git_integration
      end

      def run_checks
        check_git_repository
        check_git_branch_detection
        check_target_branch_configuration
      end

      private

      def check_git_repository
        current_branch = @git_integration.current_branch
        print_check("Git repository", :success, "current: #{current_branch}")
      rescue GitError => e
        @issues << ["Git repository not found or not configured", e.message]
        print_check("Git repository", :error)
      rescue StandardError => e
        @issues << ["Git integration failed", e.message]
        print_check("Git repository", :error)
      end

      def check_git_branch_detection
        main_branch = @git_integration.main_branch
        print_check("Git branch detection", :success, "main: #{main_branch}")
      rescue GitError, StandardError => e
        @issues << ["Git branch detection failed", e.message]
        print_check("Git branch detection", :error)
      end

      def check_target_branch_configuration
        config = MigrationGuard.configuration
        if config.target_branches&.any?
          branches = config.target_branches.join(", ")
          print_check("Target branch configuration", :success, "configured: #{branches}")
        else
          @warnings << ["No target branches configured",
                        "Consider setting config.target_branches for multi-branch workflows"]
          print_check("Target branch configuration", :warning, "using default")
        end
      end

      def puts(*args)
        @output.send(:puts, *args)
      end
    end
  end
end
