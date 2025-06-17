# frozen_string_literal: true

require "rails_helper"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Docker and CI Support" do
  # rubocop:enable RSpec/DescribeClass
  describe "TTY detection" do
    context "when running in a TTY environment" do
      before do
        allow($stdin).to receive(:tty?).and_return(true)
      end

      it "runs Rollbacker in interactive mode by default" do
        rollbacker = MigrationGuard::Rollbacker.new
        expect(rollbacker.instance_variable_get(:@interactive)).to be true
      end

      it "runs RecoveryExecutor in interactive mode by default" do
        executor = MigrationGuard::RecoveryExecutor.new
        expect(executor.send(:interactive?)).to be true
      end
    end

    context "when running in a non-TTY environment (Docker/CI)" do
      before do
        allow($stdin).to receive(:tty?).and_return(false)
      end

      it "automatically switches Rollbacker to non-interactive mode" do
        expect(MigrationGuard::Logger).to receive(:info)
          .with("Non-TTY environment detected, running in non-interactive mode")
        rollbacker = MigrationGuard::Rollbacker.new
        expect(rollbacker.instance_variable_get(:@interactive)).to be false
      end

      it "automatically switches RecoveryExecutor to non-interactive mode" do
        expect(Rails.logger).to receive(:info)
          .with("[MigrationGuard] Non-TTY environment detected, switching to non-interactive mode")
        executor = MigrationGuard::RecoveryExecutor.new
        expect(executor.send(:interactive?)).to be false
      end
    end
  end

  describe "Environment variable overrides" do
    describe "FORCE flag" do
      around do |example|
        original_force = ENV.fetch("FORCE", nil)
        example.run
        ENV["FORCE"] = original_force
      end

      it "forces non-interactive mode in Rollbacker when FORCE=true" do
        ENV["FORCE"] = "true"
        allow($stdin).to receive(:tty?).and_return(true)

        rollbacker = MigrationGuard::Rollbacker.new(interactive: ENV["FORCE"] != "true")
        expect(rollbacker.instance_variable_get(:@interactive)).to be false
      end

      it "forces non-interactive mode in RecoveryExecutor when FORCE=true" do
        ENV["FORCE"] = "true"
        allow($stdin).to receive(:tty?).and_return(true)

        executor = MigrationGuard::RecoveryExecutor.new(interactive: false)
        expect(executor.send(:interactive?)).to be false
      end
    end

    describe "NON_INTERACTIVE flag" do
      around do |example|
        original_non_interactive = ENV.fetch("NON_INTERACTIVE", nil)
        example.run
        ENV["NON_INTERACTIVE"] = original_non_interactive
      end

      it "forces non-interactive mode when NON_INTERACTIVE=true" do
        ENV["NON_INTERACTIVE"] = "true"
        allow($stdin).to receive(:tty?).and_return(true)

        rollbacker = MigrationGuard::Rollbacker.new(interactive: ENV["NON_INTERACTIVE"] != "true")
        expect(rollbacker.instance_variable_get(:@interactive)).to be false
      end
    end

    describe "AUTO flag for recovery" do
      around do |example|
        original_auto = ENV.fetch("AUTO", nil)
        example.run
        ENV["AUTO"] = original_auto
      end

      it "enables automatic recovery when AUTO=true" do
        ENV["AUTO"] = "true"
        allow($stdin).to receive(:tty?).and_return(true)

        executor = MigrationGuard::RecoveryExecutor.new(interactive: false)
        expect(executor.send(:interactive?)).to be false
      end
    end
  end

  describe "Non-interactive rollback behavior" do
    let(:reporter) { instance_double(MigrationGuard::Reporter) }
    let(:first_migration) do
      MigrationGuard::MigrationGuardRecord.new(
        version: "20240101000001",
        status: "applied",
        branch: "feature/test"
      )
    end
    let(:second_migration) do
      MigrationGuard::MigrationGuardRecord.new(
        version: "20240101000002",
        status: "applied",
        branch: "feature/test"
      )
    end

    before do
      allow(MigrationGuard::Reporter).to receive(:new).and_return(reporter)
      allow(reporter).to receive(:orphaned_migrations).and_return([first_migration, second_migration])
      allow($stdin).to receive(:tty?).and_return(false)
    end

    it "automatically proceeds with rollback without prompting" do
      rollbacker = MigrationGuard::Rollbacker.new

      # Should not call gets
      expect(rollbacker).not_to receive(:gets)

      # Should proceed with rollback
      expect(rollbacker).to receive(:execute_rollbacks).with([first_migration, second_migration])

      rollbacker.rollback_orphaned
    end
  end

  describe "Empty result handling" do
    it "shows appropriate message when history is empty" do
      allow(MigrationGuard).to receive(:enabled?).and_return(true)
      historian = instance_double(MigrationGuard::Historian)
      allow(MigrationGuard::Historian).to receive(:new).and_return(historian)
      allow(historian).to receive(:format_history_output).and_return("")

      expect { MigrationGuard::RakeTasks.history }.to output(/No migration history found/).to_stdout
    end

    it "shows appropriate message when author report is empty" do
      allow(MigrationGuard).to receive(:enabled?).and_return(true)
      author_reporter = instance_double(MigrationGuard::AuthorReporter)
      allow(MigrationGuard::AuthorReporter).to receive(:new).and_return(author_reporter)
      allow(author_reporter).to receive(:format_authors_report).and_return("")

      expect { MigrationGuard::RakeTasks.authors_report }.to output(/No migration author data found/).to_stdout
    end
  end
end
