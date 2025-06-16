# frozen_string_literal: true

require "rails_helper"

RSpec.describe MigrationGuard::BranchChangeDetector do
  let(:detector) { described_class.new }
  let(:git_integration) { instance_double(MigrationGuard::GitIntegration) }
  let(:reporter) { instance_double(MigrationGuard::Reporter) }

  before do
    allow(MigrationGuard::GitIntegration).to receive(:new).and_return(git_integration)
    allow(MigrationGuard::Reporter).to receive(:new).and_return(reporter)
    allow(git_integration).to receive(:current_branch).and_return("feature/new-feature")
    allow(Rails.logger).to receive(:info)
  end

  describe "#check_branch_change" do
    context "when not a branch checkout" do
      it "does nothing for file checkouts" do
        expect(detector).not_to receive(:branch_name_from_ref)

        detector.check_branch_change("abc123", "def456", "0")
      end
    end

    context "when warn_on_switch is disabled" do
      before do
        allow(MigrationGuard.configuration).to receive(:warn_on_switch).and_return(false)
      end

      it "does nothing" do
        expect(detector).not_to receive(:branch_name_from_ref)

        detector.check_branch_change("abc123", "def456", "1")
      end
    end

    context "when it is a branch checkout" do
      before do
        allow(MigrationGuard.configuration).to receive(:warn_on_switch).and_return(true)
      end

      it "checks for orphaned migrations" do
        allow(detector).to receive(:branch_name_from_ref).with("abc123").and_return("main")
        allow(detector).to receive(:branch_name_from_ref).with("def456").and_return("feature/new-feature")
        allow(reporter).to receive(:orphaned_migrations).and_return([])

        detector.check_branch_change("abc123", "def456", "1")

        expect(Rails.logger).to have_received(:info).with("")
        expect(Rails.logger).to have_received(:info).with(%r{Switched from 'main' to 'feature/new-feature'})
      end

      it "shows warnings when orphaned migrations exist" do
        migration = double(
          "MigrationGuardRecord",
          version: "20240115123456",
          branch: "feature/old-feature"
        )

        allow(detector).to receive(:branch_name_from_ref).with("abc123").and_return("main")
        allow(detector).to receive(:branch_name_from_ref).with("def456").and_return("feature/new-feature")
        allow(reporter).to receive(:orphaned_migrations).and_return([migration])

        detector.check_branch_change("abc123", "def456", "1")

        expect(Rails.logger).to have_received(:info).with(/Branch Change Warning/)
        expect(Rails.logger).to have_received(:info).with(%r{20240115123456.*feature/old-feature})
      end

      it "handles same branch gracefully" do
        allow(detector).to receive(:branch_name_from_ref).and_return("feature/same-branch")
        allow(git_integration).to receive(:current_branch).and_return("feature/same-branch")

        detector.check_branch_change("abc123", "def456", "1")

        expect(Rails.logger).not_to have_received(:info)
      end
    end
  end

  describe "#format_branch_change_warnings" do
    context "when no orphaned migrations exist" do
      it "returns nil" do
        allow(reporter).to receive(:orphaned_migrations).and_return([])

        expect(detector.format_branch_change_warnings).to be_nil
      end
    end

    context "when orphaned migrations exist" do
      let(:migrations) do
        [
          double(
            "MigrationGuardRecord",
            version: "20240115123456",
            branch: "feature/user-profiles"
          ),
          double(
            "MigrationGuardRecord",
            version: "20240116234567",
            branch: nil
          )
        ]
      end

      before do
        allow(reporter).to receive(:orphaned_migrations).and_return(migrations)
      end

      it "formats a warning message" do
        output = detector.format_branch_change_warnings

        aggregate_failures do
          expect(output).to include("Branch Change Warning")
          expect(output).to include("Your database has migrations not in the current branch:")
          expect(output).to include("20240115123456 (from branch: feature/user-profiles)")
          expect(output).to include("20240116234567")
          expect(output).to include("rails db:migration:status")
          expect(output).to include("rails db:migration:rollback_orphaned")
        end
      end
    end
  end
end
