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
    # Temporarily remove unique index for version conflicts testing
    ActiveRecord::Base.connection.remove_index(:migration_guard_records, :version) rescue nil
  end

  after do
    # Restore unique index after test
    ActiveRecord::Base.connection.add_index(:migration_guard_records, :version, unique: true) rescue nil
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
        # Create first record normally
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240116000001",
          status: "applied",
          branch: "main",
          metadata: { "source" => "original" }
        )
      end

      let!(:record2) do
        # Create duplicate by bypassing validation with direct SQL insert
        ActiveRecord::Base.connection.execute(
          ActiveRecord::Base.sanitize_sql([
            "INSERT INTO migration_guard_records (version, status, branch, metadata, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
            "20240116000001", "rolled_back", "feature/test", { "source" => "duplicate" }.to_json, Time.current, Time.current
          ])
        )
        # Find the record we just created
        MigrationGuard::MigrationGuardRecord.where(version: "20240116000001", status: "rolled_back").first
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
        # Create conflicts using direct SQL to bypass uniqueness validation
        records_data = [
          ["20240116000001", "applied", "main", {}],
          ["20240116000001", "rolled_back", "feature/test1", {}],
          ["20240116000002", "applied", "feature/test2", {}],
          ["20240116000002", "rolling_back", "feature/test3", {}],
          ["20240116000002", "applied", "hotfix/urgent", {}]
        ]
        
        records_data.each do |version, status, branch, metadata|
          ActiveRecord::Base.connection.execute(
            ActiveRecord::Base.sanitize_sql([
              "INSERT INTO migration_guard_records (version, status, branch, metadata, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
              version, status, branch, metadata.to_json, Time.current, Time.current
            ])
          )
        end

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
        # Create duplicates with different metadata using direct SQL
        ActiveRecord::Base.connection.execute(
          ActiveRecord::Base.sanitize_sql([
            "INSERT INTO migration_guard_records (version, status, branch, metadata, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
            "20240116000001", "applied", "main", { "migration_time" => "fast" }.to_json, 1.day.ago, 1.day.ago
          ])
        )

        ActiveRecord::Base.connection.execute(
          ActiveRecord::Base.sanitize_sql([
            "INSERT INTO migration_guard_records (version, status, branch, metadata, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
            "20240116000001", "applied", "feature/duplicate", { "migration_time" => "slow" }.to_json, 1.hour.ago, 1.hour.ago
          ])
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
        # Create 5 duplicate records using direct SQL
        5.times do |i|
          ActiveRecord::Base.connection.execute(
            ActiveRecord::Base.sanitize_sql([
              "INSERT INTO migration_guard_records (version, status, branch, metadata, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
              "20240116000001", "applied", "branch_#{i}", { "index" => i }.to_json, Time.current, Time.current
            ])
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
        # Create duplicate records using direct SQL
        ActiveRecord::Base.connection.execute(
          ActiveRecord::Base.sanitize_sql([
            "INSERT INTO migration_guard_records (version, status, branch, metadata, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
            "20240116000001", "applied", "main", {}.to_json, Time.current, Time.current
          ])
        )

        ActiveRecord::Base.connection.execute(
          ActiveRecord::Base.sanitize_sql([
            "INSERT INTO migration_guard_records (version, status, branch, metadata, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
            "20240116000001", "applied", "feature", {}.to_json, Time.current, Time.current
          ])
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
