# frozen_string_literal: true

require "rails_helper"

# rubocop:disable RSpec/IndexedLet

RSpec.describe MigrationGuard::Recovery::VersionConflictChecker do
  let(:checker) { described_class.new }

  before do
    # Clear existing data
    MigrationGuard::MigrationGuardRecord.delete_all
    # Mock time for consistent tests
    allow(Time).to receive(:current).and_return(Time.zone.parse("2024-01-16 12:00:00"))
  end

  describe "#check" do
    context "when no migration records exist" do
      it "returns empty array" do
        issues = checker.check
        expect(issues).to be_empty
      end
    end

    context "when all migration versions are unique" do
      before do
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240116000001",
          status: "applied",
          branch: "main",
          metadata: {}
        )

        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240116000002",
          status: "applied",
          branch: "feature/test",
          metadata: {}
        )
      end

      it "returns empty array" do
        issues = checker.check
        expect(issues).to be_empty
      end
    end

    context "when duplicate versions exist" do
      let!(:record1) do
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240116000001",
          status: "applied",
          branch: "main",
          metadata: { "source" => "original" }
        )
      end

      let!(:record2) do
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240116000001",
          status: "rolled_back",
          branch: "feature/test",
          metadata: { "source" => "duplicate" }
        )
      end

      it "detects version conflicts" do
        issues = checker.check

        aggregate_failures do
          expect(issues.size).to eq(1)

          issue = issues.first
          expect(issue[:type]).to eq(:version_conflict)
          expect(issue[:version]).to eq("20240116000001")
          expect(issue[:migrations]).to contain_exactly(record1, record2)
          expect(issue[:description]).to eq("Multiple records exist for the same migration version (2 records)")
          expect(issue[:severity]).to eq(:high)
          expect(issue[:recovery_options]).to include(:consolidate_records, :remove_duplicates)
        end
      end
    end

    context "when multiple versions have conflicts" do
      before do
        # First conflicted version
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240116000001",
          status: "applied",
          branch: "main",
          metadata: {}
        )
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240116000001",
          status: "rolled_back",
          branch: "feature/test1",
          metadata: {}
        )

        # Second conflicted version
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240116000002",
          status: "applied",
          branch: "feature/test2",
          metadata: {}
        )
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240116000002",
          status: "rolling_back",
          branch: "feature/test3",
          metadata: {}
        )
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240116000002",
          status: "applied",
          branch: "hotfix/urgent",
          metadata: {}
        )

        # Unique version (should not be reported)
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240116000003",
          status: "applied",
          branch: "main",
          metadata: {}
        )
      end

      it "detects all conflicts" do
        issues = checker.check

        aggregate_failures do
          expect(issues.size).to eq(2)

          conflict1 = issues.find { |i| i[:version] == "20240116000001" }
          expect(conflict1[:migrations].size).to eq(2)
          expect(conflict1[:description]).to include("2 records")

          conflict2 = issues.find { |i| i[:version] == "20240116000002" }
          expect(conflict2[:migrations].size).to eq(3)
          expect(conflict2[:description]).to include("3 records")
        end
      end
    end

    context "when records have different metadata" do
      before do
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240116000001",
          status: "applied",
          branch: "main",
          created_at: 1.day.ago,
          metadata: { "migration_time" => "fast" }
        )

        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240116000001",
          status: "applied",
          branch: "feature/duplicate",
          created_at: 1.hour.ago,
          metadata: { "migration_time" => "slow" }
        )
      end

      it "includes all conflicting records in the issue" do
        issues = checker.check
        issue = issues.first

        aggregate_failures do
          expect(issue[:migrations].size).to eq(2)

          # Verify different metadata
          metadata_values = issue[:migrations].map { |m| m.metadata["migration_time"] }
          expect(metadata_values).to contain_exactly("fast", "slow")

          # Verify different branches
          branches = issue[:migrations].map(&:branch)
          expect(branches).to contain_exactly("main", "feature/duplicate")
        end
      end
    end

    context "when checking edge case numbers" do
      it "handles large numbers of duplicates" do
        # Create 5 duplicate records
        5.times do |i|
          MigrationGuard::MigrationGuardRecord.create!(
            version: "20240116000001",
            status: "applied",
            branch: "branch_#{i}",
            metadata: { "index" => i }
          )
        end

        issues = checker.check

        aggregate_failures do
          expect(issues.size).to eq(1)
          issue = issues.first
          expect(issue[:migrations].size).to eq(5)
          expect(issue[:description]).to include("5 records")
        end
      end
    end

    context "when records have same version but different casing" do
      before do
        # Create records - versions should be treated as strings
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240116000001",
          status: "applied",
          metadata: {}
        )

        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240116000001",
          status: "applied",
          metadata: {}
        )
      end

      it "treats them as duplicates" do
        issues = checker.check

        aggregate_failures do
          expect(issues.size).to eq(1)
          expect(issues.first[:version]).to eq("20240116000001")
          expect(issues.first[:migrations].size).to eq(2)
        end
      end
    end
  end
end
