# frozen_string_literal: true

module MigrationGuard
  module RakeTasks # rubocop:disable Metrics/ModuleLength
    class << self
      def check_enabled
        return true if MigrationGuard.enabled?

        Rails.logger.info "MigrationGuard is not enabled in #{Rails.env}"
        false
      end

      def status
        return unless check_enabled

        reporter = MigrationGuard::Reporter.new
        Rails.logger.info reporter.format_status_output
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
          Rails.logger.error "Usage: rails db:migration:rollback_specific VERSION=xxx"
          return
        end

        rollbacker = MigrationGuard::Rollbacker.new
        rollbacker.rollback_specific(version)
      rescue MigrationGuard::MigrationNotFoundError, MigrationGuard::RollbackError => e
        Rails.logger.error e.message
      end

      def cleanup(force: false)
        return unless check_enabled

        unless force || ENV["FORCE"] == "true"
          days = MigrationGuard.configuration.cleanup_after_days
          Rails.logger.warn "This will delete migration tracking records older than #{days} days."
          Rails.logger.warn "To proceed, run with FORCE=true"
          return
        end

        tracker = MigrationGuard::Tracker.new
        count = tracker.cleanup_old_records
        Rails.logger.info "Cleaned up #{count} old migration tracking records"
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
        Rails.logger.info historian.format_history_output
      end

      def authors_report
        return unless check_enabled

        author_reporter = MigrationGuard::AuthorReporter.new
        Rails.logger.info author_reporter.format_authors_report
      end

      def recover
        return unless check_enabled

        analyzer = MigrationGuard::RecoveryAnalyzer.new
        issues = analyzer.analyze

        if issues.empty?
          Rails.logger.info analyzer.format_analysis_report
          return
        end

        Rails.logger.info analyzer.format_analysis_report
        Rails.logger.info "\n"

        executor = create_recovery_executor
        process_recovery_issues(issues, executor)
        log_recovery_completion(executor)
      end

      private

      def create_recovery_executor
        if ENV["AUTO"] == "true"
          Rails.logger.info Colorizer.info("Running in automatic mode...")
          MigrationGuard::RecoveryExecutor.new(interactive: false)
        else
          Rails.logger.info Colorizer.info("Running in interactive mode...")
          Rails.logger.info "Use AUTO=true to automatically apply first recovery option for each issue"
          MigrationGuard::RecoveryExecutor.new(interactive: true)
        end
      end

      def process_recovery_issues(issues, executor)
        issues.each do |issue|
          Rails.logger.info "\n#{Colorizer.info("Processing: #{issue[:type].to_s.humanize}")}"
          success = executor.execute_recovery(issue)

          if success
            Rails.logger.info Colorizer.success("✓ Issue resolved")
          else
            Rails.logger.info Colorizer.warning("⚠ Issue not resolved - manual intervention may be required")
          end
        end
      end

      def log_recovery_completion(executor)
        Rails.logger.info "\n#{Colorizer.info('Recovery process completed.')}"
        Rails.logger.info "Backup saved at: #{executor.backup_path}" if executor.backup_path
      end

      def check_git_integration
        git_integration = MigrationGuard::GitIntegration.new
        current = git_integration.current_branch
        main = git_integration.main_branch
        Rails.logger.info "✓ Git integration working"
        Rails.logger.info "  Current branch: #{current}"
        Rails.logger.info "  Main branch: #{main}"
      rescue StandardError => e
        Rails.logger.error "✗ Git integration failed: #{e.message}"
      end

      def check_database_connection
        count = MigrationGuard::MigrationGuardRecord.count
        Rails.logger.info "✓ Database connection working"
        Rails.logger.info "  Tracking records: #{count}"
      rescue StandardError => e
        Rails.logger.error "✗ Database connection failed: #{e.message}"
      end

      def show_configuration
        config = MigrationGuard.configuration
        Rails.logger.info "Configuration:"
        Rails.logger.info "  Enabled environments: #{config.enabled_environments.join(', ')}"
        Rails.logger.info "  Git integration level: #{config.git_integration_level}"
        Rails.logger.info "  Auto cleanup: #{config.auto_cleanup}"
      end
    end
  end
end
