# frozen_string_literal: true

module MigrationGuard
  module RakeTasks
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

      private

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
