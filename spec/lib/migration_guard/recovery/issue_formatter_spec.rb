# frozen_string_literal: true

require "rails_helper"

RSpec.describe MigrationGuard::Recovery::IssueFormatter do
  let(:formatter) { described_class.new }
  let(:migration) do
    MigrationGuard::MigrationGuardRecord.create!(
      version: "20240116000001",
      status: "rolling_back",
      branch: "feature/test",
      created_at: Time.zone.parse("2024-01-16 10:00:00"),
      updated_at: Time.zone.parse("2024-01-16 11:30:00"),
      metadata: {}
    )
  end

  before do
    # Clear existing data
    MigrationGuard::MigrationGuardRecord.delete_all
    # Mock Colorizer methods to return simple strings for testing
    allow(MigrationGuard::Colorizer).to receive(:error) { |text| "ERROR: #{text}" }
    allow(MigrationGuard::Colorizer).to receive(:warning) { |text| "WARNING: #{text}" }
    allow(MigrationGuard::Colorizer).to receive(:info) { |text| "INFO: #{text}" }
  end

  describe ".format" do
    it "delegates to instance method" do
      issue = { type: :partial_rollback, version: "20240116000001" }

      # rubocop:disable RSpec/AnyInstance
      expect_any_instance_of(described_class).to receive(:format).with(issue, 1)
      # rubocop:enable RSpec/AnyInstance
      described_class.format(issue, 1)
    end
  end

  describe "#format" do
    context "with minimal issue (no migration details)" do
      let(:issue) do
        {
          type: :orphaned_schema,
          version: "20240116000001",
          description: "Schema contains migration not tracked by Migration Guard",
          severity: :medium,
          recovery_options: %i[track_migration remove_from_schema]
        }
      end

      it "formats basic issue information" do
        result = formatter.format(issue, 1)

        aggregate_failures do
          expect(result).to include("ERROR: 1. Orphaned schema")
          expect(result).to include("Version: 20240116000001")
          expect(result).to include("Schema contains migration not tracked by Migration Guard")
          expect(result).to include("Severity: INFO: MEDIUM")
          expect(result).to include("Recovery options: track_migration, remove_from_schema")
          # Should not include migration details since migration is nil
          expect(result).not_to include("Branch:")
          expect(result).not_to include("Last updated:")
        end
      end
    end

    context "with complete issue (including migration details)" do
      let(:issue) do
        {
          type: :partial_rollback,
          version: migration.version,
          migration: migration,
          description: "Migration appears to be stuck in rollback state",
          severity: :high,
          recovery_options: %i[complete_rollback restore_migration mark_as_rolled_back]
        }
      end

      it "formats complete issue information" do
        result = formatter.format(issue, 2)

        aggregate_failures do
          expect(result).to include("ERROR: 2. Partial rollback")
          expect(result).to include("Version: 20240116000001")
          expect(result).to include("Migration appears to be stuck in rollback state")
          expect(result).to include("Severity: WARNING: HIGH")
          expect(result).to include("Branch: feature/test")
          expect(result).to include("Last updated: 2024-01-16 11:30:00")
          expect(result).to include("Recovery options: complete_rollback, restore_migration, mark_as_rolled_back")
        end
      end
    end

    context "with different severity levels" do
      let(:base_issue) do
        {
          type: :missing_file,
          version: "20240116000001",
          description: "Migration file is missing",
          recovery_options: %i[restore_from_git]
        }
      end

      it "formats critical severity" do
        issue = base_issue.merge(severity: :critical)
        result = formatter.format(issue, 1)
        expect(result).to include("Severity: ERROR: CRITICAL")
      end

      it "formats high severity" do
        issue = base_issue.merge(severity: :high)
        result = formatter.format(issue, 1)
        expect(result).to include("Severity: WARNING: HIGH")
      end

      it "formats medium severity" do
        issue = base_issue.merge(severity: :medium)
        result = formatter.format(issue, 1)
        expect(result).to include("Severity: INFO: MEDIUM")
      end

      it "formats low severity" do
        issue = base_issue.merge(severity: :low)
        result = formatter.format(issue, 1)
        expect(result).to include("Severity: LOW")
      end

      it "handles unknown severity" do
        issue = base_issue.merge(severity: :unknown)
        result = formatter.format(issue, 1)
        expect(result).to include("Severity: LOW")
      end
    end

    context "with different issue types" do
      let(:base_issue) do
        {
          version: "20240116000001",
          description: "Test description",
          severity: :medium,
          recovery_options: %i[test_option]
        }
      end

      it "formats snake_case type names" do
        issue = base_issue.merge(type: :version_conflict)
        result = formatter.format(issue, 1)
        expect(result).to include("ERROR: 1. Version conflict")
      end

      it "formats single word type names" do
        issue = base_issue.merge(type: :orphaned)
        result = formatter.format(issue, 1)
        expect(result).to include("ERROR: 1. Orphaned")
      end
    end

    context "with multiple recovery options" do
      let(:issue) do
        {
          type: :partial_rollback,
          version: "20240116000001",
          description: "Test description",
          severity: :high,
          recovery_options: %i[option_one option_two option_three]
        }
      end

      it "formats all options separated by commas" do
        result = formatter.format(issue, 1)
        expect(result).to include("Recovery options: option_one, option_two, option_three")
      end
    end

    context "with empty recovery options" do
      let(:issue) do
        {
          type: :test_issue,
          version: "20240116000001",
          description: "Test description",
          severity: :medium,
          recovery_options: []
        }
      end

      it "handles empty options array" do
        result = formatter.format(issue, 1)
        expect(result).to include("Recovery options: ")
      end
    end
  end

  describe "private methods" do
    describe "#format_timestamp" do
      it "formats timestamp correctly" do
        time = Time.zone.parse("2024-01-16 14:23:45")
        result = formatter.send(:format_timestamp, time)
        expect(result).to eq("2024-01-16 14:23:45")
      end
    end

    describe "#severity_color" do
      it "returns colored critical severity" do
        result = formatter.send(:severity_color, :critical)
        expect(result).to eq("ERROR: CRITICAL")
      end

      it "returns colored high severity" do
        result = formatter.send(:severity_color, :high)
        expect(result).to eq("WARNING: HIGH")
      end

      it "returns colored medium severity" do
        result = formatter.send(:severity_color, :medium)
        expect(result).to eq("INFO: MEDIUM")
      end

      it "returns uncolored low severity" do
        result = formatter.send(:severity_color, :low)
        expect(result).to eq("LOW")
      end

      it "returns uncolored unknown severity" do
        result = formatter.send(:severity_color, :unknown)
        expect(result).to eq("LOW")
      end
    end

    describe "#format_migration_details" do
      context "when issue has migration" do
        let(:issue) { { migration: migration } }

        it "returns branch and timestamp details" do
          result = formatter.send(:format_migration_details, issue)

          aggregate_failures do
            expect(result).to be_an(Array)
            expect(result.size).to eq(2)
            expect(result[0]).to include("Branch: feature/test")
            expect(result[1]).to include("Last updated: 2024-01-16 11:30:00")
          end
        end
      end

      context "when issue has no migration" do
        let(:issue) { {} }

        it "returns empty array" do
          result = formatter.send(:format_migration_details, issue)
          expect(result).to eq([])
        end
      end
    end
  end

  describe "integration with real migration data" do
    let(:real_migration) do
      MigrationGuard::MigrationGuardRecord.create!(
        version: "20240116123456",
        status: "applied",
        branch: "main",
        created_at: Time.zone.parse("2024-01-15 09:00:00"),
        updated_at: Time.zone.parse("2024-01-16 15:30:22"),
        metadata: { "direction" => "up", "execution_time" => 2.5 }
      )
    end

    let(:issue) do
      {
        type: :missing_from_schema,
        version: real_migration.version,
        migration: real_migration,
        description: "Migration tracked as applied but missing from schema",
        severity: :high,
        recovery_options: %i[reapply_migration mark_as_rolled_back]
      }
    end

    it "formats real migration data correctly" do
      result = formatter.format(issue, 3)

      aggregate_failures do
        expect(result).to include("ERROR: 3. Missing from schema")
        expect(result).to include("Version: 20240116123456")
        expect(result).to include("Migration tracked as applied but missing from schema")
        expect(result).to include("Severity: WARNING: HIGH")
        expect(result).to include("Branch: main")
        expect(result).to include("Last updated: 2024-01-16 15:30:22")
        expect(result).to include("Recovery options: reapply_migration, mark_as_rolled_back")
      end
    end
  end
end
