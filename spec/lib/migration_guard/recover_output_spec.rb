# frozen_string_literal: true

require "rails_helper"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "MigrationGuard recover command output" do
  # rubocop:enable RSpec/DescribeClass
  let(:rake_tasks) { MigrationGuard::RakeTasks }
  let(:io) { StringIO.new }
  let(:analyzer) { instance_double(MigrationGuard::RecoveryAnalyzer) }
  let(:executor) { instance_double(MigrationGuard::RecoveryExecutor) }

  before do
    allow(MigrationGuard).to receive(:enabled?).and_return(true)
    allow(MigrationGuard::Colorizer).to receive(:colorize_output?).and_return(false)
    allow($stdout).to receive(:puts) { |msg| io.puts(msg) }
    allow(MigrationGuard::RecoveryAnalyzer).to receive(:new).and_return(analyzer)
    allow(MigrationGuard::RecoveryExecutor).to receive(:new).and_return(executor)
    allow(executor).to receive(:backup_path).and_return(nil)
    # Mock TTY to default to true for tests
    allow($stdin).to receive(:tty?).and_return(true)
  end

  describe "#recover" do
    context "when no issues are found" do
      let(:report) { "✅ No recovery issues found\n\nAll migrations are in a healthy state." }

      before do
        allow(analyzer).to receive_messages(analyze: [], format_analysis_report: report)
      end

      it "displays healthy state message" do
        rake_tasks.recover

        output = io.string
        expect(output).to include("✅ No recovery issues found")
        expect(output).to include("All migrations are in a healthy state")
      end
    end

    # rubocop:disable RSpec/MultipleMemoizedHelpers
    context "when issues are found" do
      let(:issues) do
        [
          { type: :orphaned_migration, version: "20240101000001" }
        ]
      end
      let(:report) { "❌ Recovery issues detected\n\nOrphaned migrations: 1" }

      before do
        allow(analyzer).to receive_messages(analyze: issues, format_analysis_report: report)
        allow(ENV).to receive(:[]).with("AUTO").and_return(nil)
        allow(ENV).to receive(:[]).with("NON_INTERACTIVE").and_return(nil)
        allow(ENV).to receive(:[]).with("FORCE").and_return(nil)
      end

      context "when in interactive mode" do
        before do
          allow($stdin).to receive(:tty?).and_return(true)
          allow(executor).to receive(:execute_recovery).and_return(true)
        end

        it "displays analysis report and processes issues" do
          aggregate_failures do
            rake_tasks.recover

            output = io.string
            expect(output).to include("❌ Recovery issues detected")
            expect(output).to include("Orphaned migrations: 1")
            expect(output).to include("Running in interactive mode...")
            expect(output).to include("Use AUTO=true, NON_INTERACTIVE=true, or FORCE=true to automatically apply")
            expect(output).to include("Processing: Orphaned migration")
            expect(output).to include("✓ Issue resolved")
            expect(output).to include("Recovery process completed.")
          end
        end
      end

      context "when in automatic mode" do
        before do
          allow(ENV).to receive(:[]).with("AUTO").and_return("true")
          allow(executor).to receive(:execute_recovery).and_return(true)
        end

        it "displays automatic mode message" do
          rake_tasks.recover

          output = io.string
          expect(output).to include("Running in automatic mode...")
          expect(output).not_to include("Use AUTO=true")
        end
      end

      context "when recovery fails" do
        before do
          allow(executor).to receive(:execute_recovery).and_return(false)
        end

        it "displays failure message" do
          rake_tasks.recover

          output = io.string
          expect(output).to include("⚠ Issue not resolved - manual intervention may be required")
        end
      end

      context "with backup created" do
        before do
          allow(executor).to receive_messages(execute_recovery: true, backup_path: "/tmp/backup_20240101.sql")
        end

        it "displays backup path" do
          rake_tasks.recover

          output = io.string
          expect(output).to include("Backup saved at: /tmp/backup_20240101.sql")
        end
      end
    end
    # rubocop:enable RSpec/MultipleMemoizedHelpers
  end
end
