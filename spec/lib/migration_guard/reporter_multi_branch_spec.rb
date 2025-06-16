# frozen_string_literal: true

require "rails_helper"

RSpec.describe MigrationGuard::Reporter, "multi-branch support" do
  let(:reporter) { described_class.new }
  let(:git_integration) { instance_double(MigrationGuard::GitIntegration) }

  before do
    allow(MigrationGuard::GitIntegration).to receive(:new).and_return(git_integration)
    allow(git_integration).to receive(:main_branch).and_return("main")
    
    # Enable multi-branch mode
    allow(MigrationGuard.configuration).to receive(:target_branches)
      .and_return(%w[main develop staging])
    allow(git_integration).to receive(:target_branches)
      .and_return(%w[main develop staging])
  end

  def create_migration_guard_record(attributes = {})
    MigrationGuard::MigrationGuardRecord.create!({
      status: "applied",
      branch: "feature/test",
      author: "test@example.com"
    }.merge(attributes))
  end

  describe "#orphaned_migrations" do
    context "with multiple target branches" do
      before do
        allow(git_integration).to receive(:migration_versions_in_branches).and_return({
          "main" => %w[001 002],
          "develop" => %w[001 002 003],
          "staging" => %w[001 002]
        })
      end

      it "considers migrations orphaned only if missing from all branches" do
        create_migration_guard_record(version: "001", status: "applied")
        create_migration_guard_record(version: "002", status: "applied")
        create_migration_guard_record(version: "003", status: "applied")
        create_migration_guard_record(version: "004", status: "applied")

        orphaned = reporter.orphaned_migrations

        expect(orphaned.map(&:version)).to eq(["004"])
      end

      it "considers migration synced if present in any branch" do
        create_migration_guard_record(version: "001", status: "applied")
        create_migration_guard_record(version: "003", status: "applied")

        orphaned = reporter.orphaned_migrations

        expect(orphaned).to be_empty
      end
    end
  end

  describe "#missing_migrations" do
    context "with multiple target branches" do
      before do
        allow(git_integration).to receive(:migration_versions_in_branches).and_return({
          "main" => %w[001 002],
          "develop" => %w[001 002 003],
          "staging" => %w[001 002 004]
        })
      end

      it "returns missing migrations by branch" do
        create_migration_guard_record(version: "001", status: "applied")

        missing = reporter.missing_migrations

        expect(missing).to eq({
          "main" => %w[002],
          "develop" => %w[002 003],
          "staging" => %w[002 004]
        })
      end

      it "excludes branches with no missing migrations" do
        create_migration_guard_record(version: "001", status: "applied")
        create_migration_guard_record(version: "002", status: "applied")

        missing = reporter.missing_migrations

        expect(missing).to eq({
          "develop" => %w[003],
          "staging" => %w[004]
        })
      end

      it "returns empty hash when all migrations are applied" do
        %w[001 002 003 004].each do |version|
          create_migration_guard_record(version: version, status: "applied")
        end

        missing = reporter.missing_migrations

        expect(missing).to eq({})
      end
    end
  end

  describe "#status_report" do
    context "with multiple target branches" do
      before do
        allow(git_integration).to receive(:current_branch).and_return("feature/test")
        allow(git_integration).to receive(:migration_versions_in_branches).and_return({
          "main" => %w[001 002],
          "develop" => %w[001 002 003]
        })
        
        create_migration_guard_record(version: "001", status: "applied")
        create_migration_guard_record(version: "004", status: "applied")
      end

      it "returns multi-branch status report" do
        report = reporter.status_report

        aggregate_failures do
          expect(report).to include(
            current_branch: "feature/test",
            target_branches: %w[main develop staging],
            orphaned_count: 1,
            synced_count: 1
          )
          expect(report[:missing_by_branch]).to eq({
            "main" => %w[002],
            "develop" => %w[002 003]
          })
          expect(report[:missing_migrations]).to contain_exactly("002", "003")
        end
      end
    end
  end

  describe "#format_status_output" do
    before do
      allow(git_integration).to receive(:current_branch).and_return("feature/test")
    end

    context "with missing migrations in multiple branches" do
      before do
        allow(git_integration).to receive(:migration_versions_in_branches).and_return({
          "main" => %w[001 002],
          "develop" => %w[001 002 003]
        })
        
        create_migration_guard_record(version: "001", status: "applied")
      end

      it "displays missing migrations by branch" do
        output = reporter.format_status_output

        aggregate_failures do
          expect(output).to include("Migration Status (branches: main, develop, staging)")
          expect(output).to include("Missing Migrations by Branch:")
          expect(output).to include("main:")
          expect(output).to include("002")
          expect(output).to include("develop:")
          expect(output).to include("003")
          expect(output).to include("✗ Missing: 2 migrations (in target branches, not local)")
        end
      end
    end

    context "with clean status across all branches" do
      before do
        allow(git_integration).to receive(:migration_versions_in_branches).and_return({
          "main" => %w[001 002],
          "develop" => %w[001 002],
          "staging" => %w[001 002]
        })
        
        create_migration_guard_record(version: "001", status: "applied")
        create_migration_guard_record(version: "002", status: "applied")
      end

      it "displays synced status" do
        output = reporter.format_status_output

        expect(output).to include("✓ All migrations synced with main, develop, staging")
      end
    end

    context "with orphaned migrations" do
      before do
        allow(git_integration).to receive(:migration_versions_in_branches).and_return({
          "main" => %w[001],
          "develop" => %w[001],
          "staging" => %w[001]
        })
        
        create_migration_guard_record(version: "001", status: "applied")
        create_migration_guard_record(version: "002", status: "applied", branch: "feature/test")
      end

      it "displays orphaned migrations" do
        output = reporter.format_status_output

        aggregate_failures do
          expect(output).to include("⚠ Orphaned: 1 migration (local only)")
          expect(output).to include("Orphaned Migrations:")
          expect(output).to include("002")
        end
      end
    end
  end

  describe "#summary_line" do
    before do
      allow(git_integration).to receive(:current_branch).and_return("feature/test")
    end

    context "with missing migrations from multiple branches" do
      before do
        allow(git_integration).to receive(:migration_versions_in_branches).and_return({
          "main" => %w[001 002],
          "develop" => %w[001 002 003]
        })
        
        create_migration_guard_record(version: "001", status: "applied")
      end

      it "generates multi-branch missing summary" do
        summary = reporter.summary_line

        expect(summary).to eq("MigrationGuard: 2 missing migrations from branches: main, develop")
      end
    end

    context "with clean status across all branches" do
      before do
        allow(git_integration).to receive(:migration_versions_in_branches).and_return({
          "main" => %w[001],
          "develop" => %w[001],
          "staging" => %w[001]
        })
        
        create_migration_guard_record(version: "001", status: "applied")
      end

      it "generates multi-branch synced summary" do
        summary = reporter.summary_line

        expect(summary).to eq("MigrationGuard: All migrations synced with branches: main, develop, staging")
      end
    end
  end
end