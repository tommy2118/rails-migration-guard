# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Branch switching integration", type: :integration do
  let(:git_integration) { instance_double(MigrationGuard::GitIntegration) }
  let(:detector) { MigrationGuard::BranchChangeDetector.new }
  let(:test_logger) { instance_double(Logger) }

  before do
    allow(MigrationGuard::GitIntegration).to receive(:new).and_return(git_integration)

    # Setup Rails.logger properly
    allow(Rails).to receive(:logger).and_return(test_logger)
    allow(test_logger).to receive(:info)
    allow(test_logger).to receive(:debug)
    allow(test_logger).to receive(:error)

    allow(MigrationGuard).to receive(:enabled?).and_return(true)
    allow(MigrationGuard.configuration).to receive(:warn_on_switch).and_return(true)

    # Clean up any existing records
    MigrationGuard::MigrationGuardRecord.delete_all
  end

  describe "branch change detection" do
    before do
      # Setup git mocks
      allow(git_integration).to receive_messages(
        current_branch: "feature/new-feature",
        main_branch: "main",
        migration_versions_in_trunk: %w[20240101000001 20240102000001]
      )

      # Create some migration records
      # Synced migrations
      MigrationGuard::MigrationGuardRecord.create!(
        version: "20240101000001",
        status: "applied",
        branch: "main"
      )

      # Orphaned migration from another feature branch
      MigrationGuard::MigrationGuardRecord.create!(
        version: "20240115123456",
        status: "applied",
        branch: "feature/old-feature",
        author: "dev@example.com"
      )
    end

    it "detects orphaned migrations when switching branches" do
      # Simulate switching from main to feature branch
      allow(detector).to receive(:branch_name_from_ref).with("abc123").and_return("main")
      allow(detector).to receive(:branch_name_from_ref).with("def456").and_return("feature/new-feature")

      # Suppress output in tests
      allow(detector).to receive(:puts)

      detector.check_branch_change("abc123", "def456", "1")

      # Verify it output the branch switch
      expect(detector).to have_received(:puts).with("")
      expect(detector).to have_received(:puts).with(%r{Switched from 'main' to 'feature/new-feature'})

      # Verify it warned about orphaned migrations
      expect(detector).to have_received(:puts).with(/Branch Change Warning/)
    end

    it "respects the warn_on_switch configuration" do
      allow(MigrationGuard.configuration).to receive(:warn_on_switch).and_return(false)

      # Verify puts is not called
      expect(detector).not_to receive(:puts)

      detector.check_branch_change("abc123", "def456", "1")
    end

    it "provides helpful suggestions in the warning" do
      allow(detector).to receive(:branch_name_from_ref).with("abc123").and_return("main")
      allow(detector).to receive(:branch_name_from_ref).with("def456").and_return("feature/new-feature")

      # Capture output
      output = []
      allow(detector).to receive(:puts) { |msg| output << msg if msg }

      detector.check_branch_change("abc123", "def456", "1")

      # Check for helpful commands in output
      full_output = output.join("\n")
      expect(full_output).to include("rails db:migration:status")
      expect(full_output).to include("rails db:migration:rollback_orphaned")
    end
  end

  describe "rake task integration" do
    it "can be called through the rake task" do
      expect(MigrationGuard::BranchChangeDetector).to receive(:new).and_return(detector)
      expect(detector).to receive(:check_branch_change).with("abc123", "def456", "1")

      MigrationGuard::RakeTasks.check_branch_change("abc123", "def456", "1")
    end
  end
end
