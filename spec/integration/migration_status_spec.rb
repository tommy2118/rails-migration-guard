# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "Migration status checking", type: :integration do
  let(:git_integration) { instance_double(MigrationGuard::GitIntegration) }
  let(:reporter) { MigrationGuard::Reporter.new }

  before do
    # Setup git integration mocks
    allow(MigrationGuard::GitIntegration).to receive(:new).and_return(git_integration)
    allow(git_integration).to receive_messages(current_branch: "feature/user-profiles", main_branch: "main")

    # Clean up any existing records
    MigrationGuard::MigrationGuardRecord.delete_all
  end

  describe "comprehensive status report" do
    before do
      # Create some test migration records
      # Migrations that exist in main (synced)
      allow(git_integration).to receive(:migration_versions_in_trunk)
        .and_return(%w[20240101000001 20240102000001])

      # Applied migrations - some in main, some orphaned
      MigrationGuard::MigrationGuardRecord.create!(
        version: "20240101000001",
        status: "applied",
        branch: "main",
        author: "dev@example.com",
        created_at: 10.days.ago
      )

      MigrationGuard::MigrationGuardRecord.create!(
        version: "20240102000001",
        status: "applied",
        branch: "main",
        author: "dev@example.com",
        created_at: 5.days.ago
      )

      # Orphaned migrations (not in main)
      MigrationGuard::MigrationGuardRecord.create!(
        version: "20240115123456",
        status: "applied",
        branch: "feature/user-profiles",
        author: "dev@example.com",
        created_at: 2.days.ago
      )

      MigrationGuard::MigrationGuardRecord.create!(
        version: "20240114111111",
        status: "applied",
        branch: "feature/avatars",
        author: "other@example.com",
        created_at: 3.days.ago
      )
    end

    it "generates a complete status report" do
      report = reporter.status_report

      expect(report[:current_branch]).to eq("feature/user-profiles")
      expect(report[:main_branch]).to eq("main")
      expect(report[:synced_count]).to eq(2)
      expect(report[:orphaned_count]).to eq(2)
      expect(report[:missing_count]).to eq(0)

      orphaned = report[:orphaned_migrations]
      expect(orphaned).to be_an(Array)
      expect(orphaned.size).to eq(2)

      orphaned_versions = orphaned.map { |m| m[:version] }
      expect(orphaned_versions).to include("20240115123456", "20240114111111")

      user_profile_migration = orphaned.find { |m| m[:version] == "20240115123456" }
      expect(user_profile_migration[:branch]).to eq("feature/user-profiles")

      avatar_migration = orphaned.find { |m| m[:version] == "20240114111111" }
      expect(avatar_migration[:branch]).to eq("feature/avatars")
    end

    it "formats output with color coding" do
      output = reporter.format_status_output

      # Check for header
      expect(output).to include("Migration Status")
      expect(output).to include("main branch")

      # Check for summary counts
      expect(output).to include("✓ Synced:")
      expect(output).to include("2 migrations")
      expect(output).to include("⚠ Orphaned:")
      expect(output).to include("2 migrations")

      # Check for orphaned migration details
      expect(output).to include("20240115123456")
      expect(output).to include("feature/user-profiles")
      expect(output).to include("20240114111111")
      expect(output).to include("feature/avatars")

      # Check for action hint
      expect(output).to include("rails db:migration:rollback_orphaned")
    end
  end

  describe "edge cases" do
    it "handles no migrations gracefully" do
      allow(git_integration).to receive(:migration_versions_in_trunk).and_return([])

      report = reporter.status_report

      expect(report[:synced_count]).to eq(0)
      expect(report[:orphaned_count]).to eq(0)
      expect(report[:missing_count]).to eq(0)

      output = reporter.format_status_output
      expect(output).to include("✓ All migrations synced with main")
    end

    it "identifies missing migrations from trunk" do
      # Migrations in trunk but not applied locally
      allow(git_integration).to receive(:migration_versions_in_trunk)
        .and_return(%w[20240101000001 20240102000001 20240103000001])

      # Only two applied locally
      MigrationGuard::MigrationGuardRecord.create!(
        version: "20240101000001",
        status: "applied",
        branch: "main"
      )

      MigrationGuard::MigrationGuardRecord.create!(
        version: "20240102000001",
        status: "applied",
        branch: "main"
      )

      report = reporter.status_report

      expect(report[:missing_count]).to eq(1)
      expect(report[:missing_migrations]).to include("20240103000001")

      output = reporter.format_status_output
      expect(output).to include("✗ Missing:")
      expect(output).to include("1 migration")
      expect(output).to include("20240103000001")
    end

    it "excludes rolled back migrations from orphaned count" do
      allow(git_integration).to receive(:migration_versions_in_trunk)
        .and_return(["20240101000001"])

      # One synced, one orphaned, one rolled back
      MigrationGuard::MigrationGuardRecord.create!(
        version: "20240101000001",
        status: "applied",
        branch: "main"
      )

      MigrationGuard::MigrationGuardRecord.create!(
        version: "20240115123456",
        status: "applied",
        branch: "feature/test"
      )

      MigrationGuard::MigrationGuardRecord.create!(
        version: "20240116789012",
        status: "rolled_back",
        branch: "feature/test"
      )

      report = reporter.status_report

      expect(report[:orphaned_count]).to eq(1) # Only applied migrations count
      orphaned_versions = report[:orphaned_migrations].map { |m| m[:version] }
      expect(orphaned_versions).to include("20240115123456")
      expect(orphaned_versions).not_to include("20240116789012")
    end
  end

  describe "rake task integration" do
    before do
      Rails.application.load_tasks if Rake::Task.tasks.empty?
      allow(Rails.logger).to receive(:info)
      allow(MigrationGuard).to receive(:enabled?).and_return(true)
    end

    it "executes the status rake task successfully" do
      # Need to stub migration_versions_in_trunk for the reporter
      allow(git_integration).to receive(:migration_versions_in_trunk).and_return([])

      expect(MigrationGuard::Reporter).to receive(:new).and_return(reporter)
      expect(reporter).to receive(:format_status_output).and_call_original

      Rake::Task["db:migration:status"].execute
    end
  end

  describe "timestamp display" do
    it "shows relative timestamps for migrations" do
      allow(git_integration).to receive(:migration_versions_in_trunk).and_return([])

      MigrationGuard::MigrationGuardRecord.create!(
        version: "20240115123456",
        status: "applied",
        branch: "feature/test",
        author: "dev@example.com",
        created_at: 3.days.ago
      )

      output = reporter.format_status_output

      # Should show "3 days" in the age column
      expect(output).to match(/3 days?/)
    end
  end
end
