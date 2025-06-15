# frozen_string_literal: true

require "rails_helper"

RSpec.describe MigrationGuard::Reporter do
  let(:reporter) { described_class.new }
  let(:git_integration) { instance_double(MigrationGuard::GitIntegration) }

  before do
    allow(MigrationGuard::GitIntegration).to receive(:new).and_return(git_integration)
    allow(git_integration).to receive(:main_branch).and_return("main")
  end

  describe "#orphaned_migrations" do
    before do
      allow(git_integration).to receive(:migration_versions_in_trunk).and_return(%w[20240101000001 20240102000002])
    end

    context "when migrations exist only locally" do
      before do
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240101000001",
          status: "applied",
          branch: "main"
        )
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240103000003",
          status: "applied",
          branch: "feature/new-feature"
        )
      end

      it "identifies migrations not in trunk" do
        orphaned = reporter.orphaned_migrations

        aggregate_failures do
          expect(orphaned.size).to eq(1)
          expect(orphaned.first.version).to eq("20240103000003")
        end
      end
    end

    context "when all migrations are in trunk" do
      before do
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240101000001",
          status: "applied",
          branch: "main"
        )
      end

      it "returns empty array" do
        expect(reporter.orphaned_migrations).to be_empty
      end
    end

    context "with rolled back migrations" do
      before do
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240103000003",
          status: "rolled_back",
          branch: "feature/test"
        )
      end

      it "excludes rolled back migrations" do
        expect(reporter.orphaned_migrations).to be_empty
      end
    end
  end

  describe "#missing_migrations" do
    before do
      allow(git_integration).to receive(:migration_versions_in_trunk).and_return(%w[20240101000001 20240102000002
                                                                                    20240103000003])
    end

    context "when trunk has migrations not run locally" do
      before do
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240101000001",
          status: "applied",
          branch: "main"
        )
        # 20240102000002 and 20240103000003 are missing
      end

      it "identifies missing migrations" do
        missing = reporter.missing_migrations

        aggregate_failures do
          expect(missing).to eq(%w[20240102000002 20240103000003])
        end
      end
    end

    context "when all trunk migrations are applied" do
      before do
        MigrationGuard::MigrationGuardRecord.create!(version: "20240101000001", status: "applied", branch: "main")
        MigrationGuard::MigrationGuardRecord.create!(version: "20240102000002", status: "applied", branch: "main")
        MigrationGuard::MigrationGuardRecord.create!(version: "20240103000003", status: "applied", branch: "main")
      end

      it "returns empty array" do
        expect(reporter.missing_migrations).to be_empty
      end
    end
  end

  describe "#status_report" do
    before do
      allow(git_integration).to receive_messages(migration_versions_in_trunk: ["20240101000001"],
                                                 current_branch: "feature/test")
    end

    context "with mixed migration states" do
      before do
        # Synced migration
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240101000001",
          status: "applied",
          branch: "main"
        )
        # Orphaned migration
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240102000002",
          status: "applied",
          branch: "feature/test",
          author: "dev@example.com"
        )
      end

      it "generates comprehensive status report" do
        report = reporter.status_report

        aggregate_failures do
          expect(report[:current_branch]).to eq("feature/test")
          expect(report[:main_branch]).to eq("main")
          expect(report[:synced_count]).to eq(1)
          expect(report[:orphaned_count]).to eq(1)
          expect(report[:missing_count]).to eq(0)
          expect(report[:orphaned_migrations].size).to eq(1)
          expect(report[:orphaned_migrations].first).to include(
            version: "20240102000002",
            branch: "feature/test",
            author: "dev@example.com",
            status: "applied"
          )
        end
      end
    end

    context "with no migrations" do
      it "returns empty report" do
        report = reporter.status_report

        aggregate_failures do
          expect(report[:synced_count]).to eq(0)
          expect(report[:orphaned_count]).to eq(0)
          expect(report[:missing_count]).to eq(1)
          expect(report[:orphaned_migrations]).to be_empty
          expect(report[:missing_migrations]).to eq(["20240101000001"])
        end
      end
    end
  end

  describe "#format_status_output" do
    before do
      allow(git_integration).to receive_messages(migration_versions_in_trunk: ["20240101000001"],
                                                 current_branch: "feature/test")
    end

    context "with clean status" do
      before do
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240101000001",
          status: "applied",
          branch: "main"
        )
      end

      it "formats success message" do
        output = reporter.format_status_output

        aggregate_failures do
          expect(output).to include("Migration Status (main branch)")
          expect(output).to include("✓ All migrations synced with main")
          expect(output).to include("✓ Synced:    1 migration")
        end
      end
    end

    context "with orphaned migrations" do
      before do
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240102000002",
          status: "applied",
          branch: "feature/test",
          author: "dev@example.com",
          created_at: 3.days.ago
        )
      end

      it "formats warning message with details" do
        output = reporter.format_status_output

        aggregate_failures do
          expect(output).to include("⚠ Orphaned:  1 migration (local only)")
          expect(output).to include("Orphaned Migrations:")
          expect(output).to include("20240102000002")
          expect(output).to include("Branch: feature/test")
          expect(output).to include("Author: dev@example.com")
          expect(output).to include("Age: 3 days")
          expect(output).to include("Run `rails db:migration:rollback_orphaned` to clean up")
        end
      end
    end

    context "with missing migrations" do
      it "formats error message" do
        output = reporter.format_status_output

        aggregate_failures do
          expect(output).to include("✗ Missing:   1 migration (in trunk, not local)")
          expect(output).to include("Missing Migrations:")
          expect(output).to include("20240101000001")
          expect(output).to include("Run `rails db:migrate` to apply missing migrations")
        end
      end
    end
  end

  describe "#summary_line" do
    before do
      allow(git_integration).to receive_messages(migration_versions_in_trunk: [], current_branch: "feature/test")
    end

    it "generates concise summary" do
      MigrationGuard::MigrationGuardRecord.create!(
        version: "20240101000001",
        status: "applied",
        branch: "feature/test"
      )

      summary = reporter.summary_line

      expect(summary).to eq("MigrationGuard: 1 orphaned migration detected on branch 'feature/test'")
    end

    it "pluralizes correctly" do
      2.times do |i|
        MigrationGuard::MigrationGuardRecord.create!(
          version: "2024010100000#{i}",
          status: "applied",
          branch: "feature/test"
        )
      end

      summary = reporter.summary_line

      expect(summary).to eq("MigrationGuard: 2 orphaned migrations detected on branch 'feature/test'")
    end

    it "reports clean status" do
      summary = reporter.summary_line

      expect(summary).to eq("MigrationGuard: All migrations synced with main")
    end
  end
end
