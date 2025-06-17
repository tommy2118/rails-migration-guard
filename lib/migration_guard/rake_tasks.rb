# frozen_string_literal: true

require_relative "interactive_mode"

module MigrationGuard
  # rubocop:disable Metrics/ModuleLength
  module RakeTasks
    # rubocop:disable Metrics/ClassLength
    class << self
      def check_enabled
        return true if MigrationGuard.enabled?

        Rails.logger&.info "MigrationGuard is not enabled in #{Rails.env}"
        false
      end

      def status
        return unless check_enabled

        reporter = MigrationGuard::Reporter.new
        output = reporter.format_status_output

        # Always show output to console for user-facing commands
        puts output unless output.empty? # rubocop:disable Rails/Output
      end

      def rollback_orphaned
        return unless check_enabled

        rollbacker = MigrationGuard::Rollbacker.new
        rollbacker.rollback_orphaned
      end

      def rollback_all
        return unless check_enabled

        rollbacker = MigrationGuard::Rollbacker.new(interactive: false)
        rollbacker.rollback_all_orphaned
      end

      def rollback_specific(version)
        return unless check_enabled

        unless version
          puts Colorizer.error("Usage: rails db:migration:rollback_specific VERSION=xxx") # rubocop:disable Rails/Output
          return
        end

        rollbacker = MigrationGuard::Rollbacker.new
        rollbacker.rollback_specific(version)
      rescue MigrationGuard::MigrationNotFoundError, MigrationGuard::RollbackError => e
        puts Colorizer.error("❌ #{e.message}") # rubocop:disable Rails/Output
      end

      def cleanup(force: false)
        return unless check_enabled

        unless force || ENV["FORCE"] == "true"
          days = MigrationGuard.configuration.cleanup_after_days
          puts Colorizer.warning("This will delete migration tracking records older than #{days} days.") # rubocop:disable Rails/Output
          puts Colorizer.warning("To proceed, run with FORCE=true") # rubocop:disable Rails/Output
          return
        end

        tracker = MigrationGuard::Tracker.new
        count = tracker.cleanup_old_records
        puts Colorizer.success("✓ Cleaned up #{count} old migration tracking records") # rubocop:disable Rails/Output
      end

      def doctor
        return unless check_enabled

        diagnostics = DiagnosticRunner.new
        diagnostics.run_all_checks
      end

      def check_branch_change(previous_head, new_head, is_branch_checkout)
        return unless check_enabled

        detector = MigrationGuard::BranchChangeDetector.new
        detector.check_branch_change(previous_head, new_head, is_branch_checkout)
      end

      def history(options = {})
        return unless check_enabled

        historian = MigrationGuard::Historian.new(options)
        output = historian.format_history_output

        # Always show output to console for user-facing commands
        if output.empty?
          puts Colorizer.info("No migration history found matching the specified criteria.") # rubocop:disable Rails/Output
        else
          puts output # rubocop:disable Rails/Output
        end
      end

      def authors_report
        return unless check_enabled

        author_reporter = MigrationGuard::AuthorReporter.new
        output = author_reporter.format_authors_report

        # Always show output to console for user-facing commands
        if output.empty?
          puts Colorizer.info("No migration author data found.") # rubocop:disable Rails/Output
        else
          puts output # rubocop:disable Rails/Output
        end
      end

      def recover
        return unless check_enabled

        analyzer = MigrationGuard::RecoveryAnalyzer.new
        issues = analyzer.analyze

        if issues.empty?
          puts analyzer.format_analysis_report # rubocop:disable Rails/Output
          return
        end

        puts analyzer.format_analysis_report # rubocop:disable Rails/Output
        puts # rubocop:disable Rails/Output

        executor = create_recovery_executor
        process_recovery_issues(issues, executor)
        log_recovery_completion(executor)
      end

      # rubocop:disable Metrics/MethodLength
      def ci(format: "text", strict: false, strictness: nil)
        # CI command doesn't use check_enabled as it needs to run in all environments
        # and report the disabled status explicitly

        runner = MigrationGuard::CiRunner.new(
          format: format,
          strict: strict,
          strictness: strictness
        )

        runner.run
      rescue StandardError => e
        # Handle initialization or runtime errors
        error_output = if format.to_s.downcase == "json"
                         JSON.pretty_generate(
                           migration_guard: {
                             status: "error",
                             error: e.message,
                             exit_code: MigrationGuard::CiRunner::EXIT_ERROR
                           }
                         )
                       else
                         "❌ Error running Migration Guard CI check:\n   #{e.message}"
                       end

        puts error_output # rubocop:disable Rails/Output
        MigrationGuard::CiRunner::EXIT_ERROR
      end
      # rubocop:enable Metrics/MethodLength

      def setup
        return unless check_enabled

        require_relative "setup_assistant"
        assistant = MigrationGuard::SetupAssistant.new
        assistant.run_setup
      end

      private

      def create_recovery_executor
        if InteractiveMode.forced_non_interactive?
          puts Colorizer.info("Running in automatic mode...") # rubocop:disable Rails/Output
          MigrationGuard::RecoveryExecutor.new(interactive: false)
        else
          puts Colorizer.info("Running in interactive mode...") # rubocop:disable Rails/Output
          # rubocop:disable Rails/Output, Layout/LineLength
          puts "Use AUTO=true, NON_INTERACTIVE=true, or FORCE=true to automatically apply first recovery option for each issue"
          # rubocop:enable Rails/Output, Layout/LineLength
          MigrationGuard::RecoveryExecutor.new(interactive: true)
        end
      end

      def process_recovery_issues(issues, executor)
        issues.each do |issue|
          puts # rubocop:disable Rails/Output
          puts Colorizer.info("Processing: #{issue[:type].to_s.humanize}") # rubocop:disable Rails/Output
          success = executor.execute_recovery(issue)

          if success
            puts Colorizer.success("✓ Issue resolved") # rubocop:disable Rails/Output
          else
            puts Colorizer.warning("⚠ Issue not resolved - manual intervention may be required") # rubocop:disable Rails/Output
          end
        end
      end

      def log_recovery_completion(executor)
        puts # rubocop:disable Rails/Output
        puts Colorizer.info("Recovery process completed.") # rubocop:disable Rails/Output
        puts Colorizer.info("Backup saved at: #{executor.backup_path}") if executor.backup_path # rubocop:disable Rails/Output
      end

      def check_git_integration
        git_integration = MigrationGuard::GitIntegration.new
        current = git_integration.current_branch
        main = git_integration.main_branch
        Rails.logger&.info "✓ Git integration working"
        Rails.logger&.info "  Current branch: #{current}"
        Rails.logger&.info "  Main branch: #{main}"
      rescue StandardError => e
        Rails.logger&.error "✗ Git integration failed: #{e.message}"
      end

      def check_database_connection
        count = MigrationGuard::MigrationGuardRecord.count
        Rails.logger&.info "✓ Database connection working"
        Rails.logger&.info "  Tracking records: #{count}"
      rescue StandardError => e
        Rails.logger&.error "✗ Database connection failed: #{e.message}"
      end

      def show_configuration
        config = MigrationGuard.configuration
        Rails.logger&.info "Configuration:"
        Rails.logger&.info "  Enabled environments: #{config.enabled_environments.join(', ')}"
        Rails.logger&.info "  Git integration level: #{config.git_integration_level}"
        Rails.logger&.info "  Auto cleanup: #{config.auto_cleanup}"
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
  # rubocop:enable Metrics/ModuleLength
end
