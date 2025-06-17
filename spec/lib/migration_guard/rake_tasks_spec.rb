# frozen_string_literal: true

require "rails_helper"

RSpec.describe MigrationGuard::RakeTasks do
  let(:logger) { instance_double(Logger) }

  before do
    allow(Rails).to receive(:logger).and_return(logger)
    allow(logger).to receive(:info)
    allow(logger).to receive(:error)
    allow(logger).to receive(:warn)
  end

  describe ".status" do
    context "when MigrationGuard is enabled" do
      before do
        allow(MigrationGuard).to receive(:enabled?).and_return(true)
      end

      it "creates a reporter and logs the formatted output" do
        reporter = instance_double(MigrationGuard::Reporter)
        formatted_output = "Migration Status\n================"

        expect(MigrationGuard::Reporter).to receive(:new).and_return(reporter)
        expect(reporter).to receive(:format_status_output).and_return(formatted_output)
        expect($stdout).to receive(:puts).with(formatted_output)

        described_class.status
      end
    end

    context "when MigrationGuard is disabled" do
      before do
        allow(MigrationGuard).to receive(:enabled?).and_return(false)
        allow(Rails).to receive(:env).and_return("production")
      end

      it "logs a message and returns early" do
        expect(logger).to receive(:info).with("MigrationGuard is not enabled in production")
        expect(MigrationGuard::Reporter).not_to receive(:new)

        described_class.status
      end
    end
  end

  describe ".rollback_orphaned" do
    context "when MigrationGuard is enabled" do
      before do
        allow(MigrationGuard).to receive(:enabled?).and_return(true)
      end

      it "creates a rollbacker and calls rollback_orphaned" do
        rollbacker = instance_double(MigrationGuard::Rollbacker)

        expect(MigrationGuard::Rollbacker).to receive(:new).and_return(rollbacker)
        expect(rollbacker).to receive(:rollback_orphaned)

        described_class.rollback_orphaned
      end
    end

    context "when MigrationGuard is disabled" do
      before do
        allow(MigrationGuard).to receive(:enabled?).and_return(false)
      end

      it "returns early without creating a rollbacker" do
        expect(MigrationGuard::Rollbacker).not_to receive(:new)

        described_class.rollback_orphaned
      end
    end
  end

  describe ".rollback_all" do
    context "when MigrationGuard is enabled" do
      before do
        allow(MigrationGuard).to receive(:enabled?).and_return(true)
      end

      it "creates a non-interactive rollbacker and calls rollback_all_orphaned" do
        rollbacker = instance_double(MigrationGuard::Rollbacker)

        expect(MigrationGuard::Rollbacker).to receive(:new).with(interactive: false).and_return(rollbacker)
        expect(rollbacker).to receive(:rollback_all_orphaned)

        described_class.rollback_all
      end
    end
  end

  describe ".rollback_specific" do
    context "when MigrationGuard is enabled" do
      before do
        allow(MigrationGuard).to receive(:enabled?).and_return(true)
      end

      context "with a version provided" do
        it "creates a rollbacker and calls rollback_specific with the version" do
          rollbacker = instance_double(MigrationGuard::Rollbacker)
          version = "20240115123456"

          expect(MigrationGuard::Rollbacker).to receive(:new).and_return(rollbacker)
          expect(rollbacker).to receive(:rollback_specific).with(version)

          described_class.rollback_specific(version)
        end

        it "handles MigrationNotFoundError gracefully" do
          rollbacker = instance_double(MigrationGuard::Rollbacker)
          version = "20240115123456"
          error_message = "Migration not found: #{version}"

          expect(MigrationGuard::Rollbacker).to receive(:new).and_return(rollbacker)
          expect(rollbacker).to receive(:rollback_specific)
            .with(version)
            .and_raise(MigrationGuard::MigrationNotFoundError, error_message)
          expect($stdout).to receive(:puts).with(/❌.*#{Regexp.escape(error_message)}/)

          described_class.rollback_specific(version)
        end

        it "handles RollbackError gracefully" do
          rollbacker = instance_double(MigrationGuard::Rollbacker)
          version = "20240115123456"
          error_message = "Failed to rollback migration"

          expect(MigrationGuard::Rollbacker).to receive(:new).and_return(rollbacker)
          expect(rollbacker).to receive(:rollback_specific).with(version)
                                                           .and_raise(MigrationGuard::RollbackError, error_message)
          expect($stdout).to receive(:puts).with(/❌.*#{Regexp.escape(error_message)}/)

          described_class.rollback_specific(version)
        end
      end

      context "without a version" do
        it "logs usage instructions and returns" do
          expect($stdout).to receive(:puts).with(/Usage: rails db:migration:rollback_specific VERSION=xxx/)
          expect(MigrationGuard::Rollbacker).not_to receive(:new)

          described_class.rollback_specific(nil)
        end
      end
    end
  end

  describe ".cleanup" do
    context "when MigrationGuard is enabled" do
      before do
        allow(MigrationGuard).to receive(:enabled?).and_return(true)
        allow(MigrationGuard.configuration).to receive(:cleanup_after_days).and_return(30)
      end

      context "with force: true" do
        it "performs cleanup and logs the result" do
          tracker = instance_double(MigrationGuard::Tracker)

          expect(MigrationGuard::Tracker).to receive(:new).and_return(tracker)
          expect(tracker).to receive(:cleanup_old_records).and_return(5)
          expect(logger).to receive(:info).with("Cleaned up 5 old migration tracking records")

          described_class.cleanup(force: true)
        end
      end

      context "without force" do
        it "logs a warning and does not perform cleanup" do
          expect(logger).to receive(:warn).with("This will delete migration tracking records older than 30 days.")
          expect(logger).to receive(:warn).with("To proceed, run with FORCE=true")
          expect(MigrationGuard::Tracker).not_to receive(:new)

          described_class.cleanup(force: false)
        end
      end
    end
  end

  describe ".doctor" do
    context "when MigrationGuard is enabled" do
      before do
        allow(MigrationGuard).to receive(:enabled?).and_return(true)
      end

      it "creates a diagnostic runner and calls run_all_checks" do
        diagnostic_runner = instance_double(MigrationGuard::DiagnosticRunner)

        expect(MigrationGuard::DiagnosticRunner).to receive(:new).and_return(diagnostic_runner)
        expect(diagnostic_runner).to receive(:run_all_checks)

        described_class.doctor
      end
    end
  end
end
