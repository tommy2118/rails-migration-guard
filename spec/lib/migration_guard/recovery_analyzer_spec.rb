# frozen_string_literal: true

require "rails_helper"

RSpec.describe MigrationGuard::RecoveryAnalyzer do
  let(:analyzer) { described_class.new }
  let(:git_integration) { instance_double(MigrationGuard::GitIntegration) }

  before do
    # Clean up any existing records
    MigrationGuard::MigrationGuardRecord.delete_all

    # Mock git integration
    allow(MigrationGuard::GitIntegration).to receive(:new).and_return(git_integration)
    allow(git_integration).to receive_messages(
      current_branch: "feature/test",
      main_branch: "main"
    )

    # Clear schema_migrations for tests
    ActiveRecord::Base.connection.execute("DELETE FROM schema_migrations")
  end

  describe "#analyze" do
    it "returns empty array when no issues found" do
      issues = analyzer.analyze
      expect(issues).to be_empty
    end

    context "with partial rollbacks" do
      it "detects stuck rollback states" do
        setup_stuck_rollback_state("20240101000001")

        issues = analyzer.analyze
        partial_rollback = issues.find { |i| i[:type] == :partial_rollback }

        aggregate_failures do
          expect(partial_rollback).not_to be_nil
          expect(partial_rollback[:type]).to eq(:partial_rollback)
          expect(partial_rollback[:version]).to eq("20240101000001")
          expect(partial_rollback[:severity]).to eq(:high)
          expect(partial_rollback[:recovery_options]).to include(:complete_rollback, :restore_migration)
        end
      end

      def setup_stuck_rollback_state(version)
        allow(Dir).to receive(:glob).and_return(["db/migrate/#{version}_test.rb"])

        MigrationGuard::MigrationGuardRecord.create!(
          version: version,
          status: "rolling_back",
          branch: "feature/test",
          created_at: 2.hours.ago,
          updated_at: 2.hours.ago
        )

        ActiveRecord::Base.connection.execute(
          ActiveRecord::Base.sanitize_sql(
            ["INSERT INTO schema_migrations (version) VALUES (?)", version]
          )
        )
      end

      it "ignores recent rolling_back states" do
        # Create migration file so it doesn't report as missing
        allow(Dir).to receive(:glob).and_return(["db/migrate/20240101000001_test.rb"])

        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240101000001",
          status: "rolling_back",
          branch: "feature/test",
          created_at: 5.minutes.ago,
          updated_at: 5.minutes.ago
        )

        issues = analyzer.analyze
        expect(issues).to be_empty
      end
    end

    context "with orphaned schema changes" do
      it "detects schema entries without tracking records" do
        # Add to schema without tracking record
        ActiveRecord::Base.connection.execute(
          ActiveRecord::Base.sanitize_sql(
            ["INSERT INTO schema_migrations (version) VALUES (?)", "20240102000001"]
          )
        )

        issues = analyzer.analyze

        aggregate_failures do
          expect(issues.size).to eq(1)
          expect(issues.first[:type]).to eq(:orphaned_schema)
          expect(issues.first[:version]).to eq("20240102000001")
          expect(issues.first[:recovery_options]).to include(:track_migration, :remove_from_schema)
        end
      end

      it "detects tracked migrations missing from schema" do
        # Mock file existence
        allow(Dir).to receive(:glob).and_return(["db/migrate/20240103000001_test.rb"])

        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240103000001",
          status: "applied",
          branch: "main"
        )

        issues = analyzer.analyze

        missing_from_schema = issues.find { |i| i[:type] == :missing_from_schema }

        aggregate_failures do
          expect(missing_from_schema).not_to be_nil
          expect(missing_from_schema[:type]).to eq(:missing_from_schema)
          expect(missing_from_schema[:version]).to eq("20240103000001")
          expect(missing_from_schema[:severity]).to eq(:high)
          expect(missing_from_schema[:recovery_options]).to include(:reapply_migration, :mark_as_rolled_back)
        end
      end
    end

    context "with missing migration files" do
      it "detects missing files for applied migrations" do
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240104000001",
          status: "applied",
          branch: "main"
        )

        # File doesn't exist by default in test
        issues = analyzer.analyze

        aggregate_failures do
          expect(issues.size).to eq(2) # One for missing file, one for missing from schema
          missing_file_issue = issues.find { |i| i[:type] == :missing_file }
          expect(missing_file_issue).not_to be_nil
          expect(missing_file_issue[:severity]).to eq(:critical)
          expect(missing_file_issue[:recovery_options]).to include(:restore_from_git, :create_placeholder)
        end
      end
    end

    context "with version conflicts" do
      it "detects duplicate tracking records" do # rubocop:disable RSpec/ExampleLength
        # Mock file existence
        allow(Dir).to receive(:glob).and_return(["db/migrate/20240105000001_test.rb"])

        # Create a record
        record = MigrationGuard::MigrationGuardRecord.create!(
          version: "20240105000001",
          status: "applied",
          branch: "main"
        )

        # Create a second record object to simulate duplicate
        duplicate_record = record.dup
        duplicate_record.id = record.id + 1
        duplicate_record.branch = "feature"

        # Mock only the specific calls we need for duplicate detection
        group_mock = double
        allow(MigrationGuard::MigrationGuardRecord).to receive(:group).with(:version).and_return(group_mock)
        allow(group_mock).to receive(:count).and_return({ "20240105000001" => 2 })

        # Mock the where query for duplicate records
        allow(MigrationGuard::MigrationGuardRecord).to receive(:where).and_call_original
        allow(MigrationGuard::MigrationGuardRecord).to receive(:where)
          .with(version: "20240105000001")
          .and_return([record, duplicate_record])

        issues = analyzer.analyze
        version_conflict = issues.find { |i| i[:type] == :version_conflict }

        aggregate_failures do
          expect(version_conflict).not_to be_nil
          expect(version_conflict[:version]).to eq("20240105000001")
          expect(version_conflict[:migrations]).to include(record, duplicate_record)
          expect(version_conflict[:recovery_options]).to include(:consolidate_records, :remove_duplicates)
        end
      end
    end
  end

  describe "#issues?" do
    it "returns false when no issues" do
      expect(analyzer.issues?).to be false
    end

    it "returns true when issues exist" do
      MigrationGuard::MigrationGuardRecord.create!(
        version: "20240101000001",
        status: "rolling_back",
        created_at: 2.hours.ago,
        updated_at: 2.hours.ago
      )

      analyzer.analyze
      expect(analyzer.issues?).to be true
    end
  end

  describe "#format_analysis_report" do
    context "with no issues" do
      it "returns success message" do
        report = analyzer.format_analysis_report
        expect(report).to include("No migration inconsistencies detected")
      end
    end

    context "with issues" do
      before do
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240101000001",
          status: "rolling_back",
          branch: "feature/test",
          created_at: 2.hours.ago,
          updated_at: 2.hours.ago
        )

        ActiveRecord::Base.connection.execute(
          ActiveRecord::Base.sanitize_sql(
            ["INSERT INTO schema_migrations (version) VALUES (?)", "20240101000001"]
          )
        )

        analyzer.analyze
      end

      it "formats issues with details" do
        report = analyzer.format_analysis_report

        aggregate_failures do
          expect(report).to include("Detected migration inconsistencies")
          expect(report).to include("Partial rollback")
          expect(report).to include("20240101000001")
          expect(report).to include("stuck in rollback state")
          expect(report).to include("Severity: HIGH")
          expect(report).to include("Recovery options:")
          expect(report).to include("rails db:migration:recover")
        end
      end
    end
  end
end
