# frozen_string_literal: true

require "rails_helper"

RSpec.describe MigrationGuard::Recovery::FileChecker do
  let(:checker) { described_class.new }

  before do
    # Clear existing data
    MigrationGuard::MigrationGuardRecord.delete_all
    # Mock time for consistent tests
    allow(Time).to receive(:current).and_return(Time.zone.parse("2024-01-16 12:00:00"))
  end

  describe "#check" do
    context "when all migration files exist" do
      it "returns empty array" do
        # Create migration record with existing file
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240116000001",
          status: "applied",
          metadata: {}
        )

        # Mock file existence
        allow(Dir).to receive(:glob)
          .with(File.join(Dir.pwd, "db/migrate/20240116000001_*.rb"))
          .and_return(["db/migrate/20240116000001_create_test.rb"])

        issues = checker.check
        expect(issues).to be_empty
      end
    end

    context "when migration files are missing" do
      let!(:applied_migration) do
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240116000001",
          status: "applied",
          branch: "feature/test",
          metadata: {}
        )
      end

      let!(:rolling_back_migration) do
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240116000002",
          status: "rolling_back",
          branch: "feature/test2",
          metadata: {}
        )
      end

      before do
        # Mock missing files
        allow(Dir).to receive(:glob).and_return([])
      end

      it "detects missing files for applied migrations" do
        issues = checker.check

        missing_file_issue = issues.find { |i| i[:version] == "20240116000001" }

        aggregate_failures do
          expect(missing_file_issue).not_to be_nil
          expect(missing_file_issue[:type]).to eq(:missing_file)
          expect(missing_file_issue[:migration]).to eq(applied_migration)
          expect(missing_file_issue[:description]).to eq("Migration file is missing")
          expect(missing_file_issue[:severity]).to eq(:critical)
          expect(missing_file_issue[:recovery_options]).to include(
            :restore_from_git, :mark_as_resolved, :create_placeholder
          )
        end
      end

      it "detects missing files for rolling_back migrations" do
        issues = checker.check

        missing_file_issue = issues.find { |i| i[:version] == "20240116000002" }

        aggregate_failures do
          expect(missing_file_issue).not_to be_nil
          expect(missing_file_issue[:type]).to eq(:missing_file)
          expect(missing_file_issue[:migration]).to eq(rolling_back_migration)
          expect(missing_file_issue[:severity]).to eq(:critical)
        end
      end

      it "returns multiple issues when multiple files are missing" do
        issues = checker.check

        aggregate_failures do
          expect(issues.size).to eq(2)
          expect(issues.map { |i| i[:version] }).to contain_exactly(
            "20240116000001", "20240116000002"
          )
        end
      end
    end

    context "when only some migration files are missing" do
      before do
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240116000001",
          status: "applied",
          metadata: {}
        )

        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240116000002",
          status: "applied",
          metadata: {}
        )

        # Mock one file exists, one doesn't
        allow(Dir).to receive(:glob) do |pattern|
          # rubocop:disable Lint/DuplicateBranch
          case pattern
          when File.join(Dir.pwd, "db/migrate/20240116000001_*.rb")
            ["db/migrate/20240116000001_create_test.rb"]
          when File.join(Dir.pwd, "db/migrate/20240116000002_*.rb")
            # Migration 2 files are missing
            []
          else
            # Default case for other patterns - no files found
            []
          end
          # rubocop:enable Lint/DuplicateBranch
        end
      end

      it "only reports missing files" do
        issues = checker.check

        aggregate_failures do
          expect(issues.size).to eq(1)
          expect(issues.first[:version]).to eq("20240116000002")
          expect(issues.first[:type]).to eq(:missing_file)
        end
      end
    end

    context "when migrations have different statuses" do
      before do
        # Create migrations with various statuses
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240116000001",
          status: "applied",
          metadata: {}
        )

        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240116000002",
          status: "rolled_back",
          metadata: {}
        )

        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240116000003",
          status: "rolling_back",
          metadata: {}
        )

        # Mock no files exist
        allow(Dir).to receive(:glob).and_return([])
      end

      it "only checks applied and rolling_back migrations" do
        issues = checker.check

        aggregate_failures do
          expect(issues.size).to eq(2)
          expect(issues.map { |i| i[:version] }).to contain_exactly(
            "20240116000001", "20240116000003"
          )
          # Should not include rolled_back migration
          expect(issues.map { |i| i[:version] }).not_to include("20240116000002")
        end
      end
    end

    context "when no active migrations exist" do
      before do
        # Create only rolled_back migrations
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240116000001",
          status: "rolled_back",
          metadata: {}
        )
      end

      it "returns empty array" do
        issues = checker.check
        expect(issues).to be_empty
      end
    end
  end
end
