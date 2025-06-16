# frozen_string_literal: true

# rubocop:disable RSpec/MultipleMemoizedHelpers

require "rails_helper"

RSpec.describe MigrationGuard::Recovery::TrackingAction do
  let(:tracking_action) { described_class.new }
  let(:git_integration) { instance_double(MigrationGuard::GitIntegration) }

  before do
    allow(MigrationGuard::GitIntegration).to receive(:new).and_return(git_integration)
    allow(git_integration).to receive_messages(
      current_branch: "feature/test-branch",
      current_author: "test@example.com"
    )
    allow(Time).to receive(:current).and_return(Time.zone.parse("2024-01-16 12:00:00"))
  end

  describe "#track_migration" do
    let(:issue) { { version: "20240116000001" } }

    context "when tracking succeeds" do
      it "creates a new tracking record" do
        expect(tracking_action).to receive(:log_info).with("Tracking migration #{issue[:version]}...")
        expect(tracking_action).to receive(:log_success).with("✓ Migration tracked: #{issue[:version]}")

        result = tracking_action.track_migration(issue)

        aggregate_failures do
          expect(result).to be true

          record = MigrationGuard::MigrationGuardRecord.find_by(version: issue[:version])
          expect(record).not_to be_nil
          expect(record.branch).to eq("feature/test-branch")
          expect(record.author).to eq("test@example.com")
          expect(record.status).to eq("applied")
          expect(record.metadata).to eq({
                                          "recovery_action" => "tracked_retrospectively",
                                          "tracked_at" => "2024-01-16T12:00:00Z"
                                        })
        end
      end
    end

    context "when git operations fail" do
      before do
        allow(git_integration).to receive(:current_branch).and_raise(StandardError, "Git error")
        allow(git_integration).to receive(:current_author).and_raise(StandardError, "Git error")
      end

      it "uses fallback values" do
        result = tracking_action.track_migration(issue)

        aggregate_failures do
          expect(result).to be true

          record = MigrationGuard::MigrationGuardRecord.find_by(version: issue[:version])
          expect(record.branch).to eq("unknown")
          expect(record.author).to be_nil
        end
      end
    end

    context "when tracking fails" do
      it "returns false and logs error" do
        # Create duplicate to cause uniqueness violation
        MigrationGuard::MigrationGuardRecord.create!(
          version: issue[:version],
          status: "applied"
        )

        expect(tracking_action).to receive(:log_error).with(/Failed to track migration/)

        result = tracking_action.track_migration(issue)
        expect(result).to be false
      end
    end
  end

  describe "#consolidate_records" do
    let!(:oldest_record) do
      MigrationGuard::MigrationGuardRecord.create!(
        version: "20240116000002",
        status: "applied",
        branch: "main",
        metadata: { "key1" => "value1" },
        updated_at: 2.hours.ago
      )
    end

    let!(:middle_record) do
      MigrationGuard::MigrationGuardRecord.create!(
        version: "20240116000003",
        status: "applied",
        branch: "feature",
        metadata: { "key2" => "value2" },
        updated_at: 1.hour.ago
      )
    end

    let!(:newest_record) do
      MigrationGuard::MigrationGuardRecord.create!(
        version: "20240116000004",
        status: "rolled_back",
        branch: "develop",
        metadata: { "key3" => "value3" },
        updated_at: Time.current
      )
    end

    let(:issue) do
      {
        version: "20240116000002",
        migrations: [oldest_record, middle_record, newest_record]
      }
    end

    it "keeps the most recently updated record" do
      expect(tracking_action).to receive(:log_info).with("Consolidating 3 records for version #{issue[:version]}...")
      expect(tracking_action).to receive(:log_success).with("✓ Consolidated 3 records into one")

      result = tracking_action.consolidate_records(issue)

      aggregate_failures do
        expect(result).to be true
        expect(MigrationGuard::MigrationGuardRecord.exists?(oldest_record.id)).to be false
        expect(MigrationGuard::MigrationGuardRecord.exists?(middle_record.id)).to be false
        expect(MigrationGuard::MigrationGuardRecord.exists?(newest_record.id)).to be true
      end
    end

    it "merges metadata from all records" do
      tracking_action.consolidate_records(issue)

      newest_record.reload
      expect(newest_record.metadata).to include(
        "key1" => "value1",
        "key2" => "value2",
        "key3" => "value3",
        "consolidated_at" => "2024-01-16T12:00:00Z",
        "consolidated_from_count" => "3"
      )
    end

    it "handles arrays of records" do
      issue_with_array = { version: "20240116000002", migrations: [oldest_record, middle_record] }

      result = tracking_action.consolidate_records(issue_with_array)

      aggregate_failures do
        expect(result).to be true
        expect(MigrationGuard::MigrationGuardRecord.count).to eq(2) # newest_record remains
      end
    end

    context "when consolidation fails" do
      it "returns false and logs error" do
        allow(tracking_action).to receive(:perform_consolidation).and_raise(StandardError, "Database error")
        expect(tracking_action).to receive(:log_error).with("✗ Failed to consolidate records: Database error")

        result = tracking_action.consolidate_records(issue)
        expect(result).to be false
      end
    end
  end

  describe "#remove_duplicates" do
    let!(:applied_record) do
      MigrationGuard::MigrationGuardRecord.create!(
        version: "20240116000005",
        status: "applied",
        updated_at: 2.hours.ago
      )
    end

    let!(:rolled_back_record) do
      MigrationGuard::MigrationGuardRecord.create!(
        version: "20240116000006",
        status: "rolled_back",
        updated_at: 1.hour.ago
      )
    end

    let!(:newest_record) do
      MigrationGuard::MigrationGuardRecord.create!(
        version: "20240116000007",
        status: "rolled_back",
        updated_at: Time.current
      )
    end

    context "when there's an applied record" do
      let(:issue) do
        {
          version: "20240116000005",
          migrations: [applied_record, rolled_back_record]
        }
      end

      it "keeps the applied record and removes others" do
        expect(tracking_action).to receive(:log_info)
          .with("Removing duplicate records for version #{issue[:version]}...")
        expect(tracking_action).to receive(:log_success).with("✓ Removed 1 duplicate records")

        result = tracking_action.remove_duplicates(issue)

        aggregate_failures do
          expect(result).to be true
          expect(MigrationGuard::MigrationGuardRecord.exists?(applied_record.id)).to be true
          expect(MigrationGuard::MigrationGuardRecord.exists?(rolled_back_record.id)).to be false
          expect(MigrationGuard::MigrationGuardRecord.exists?(newest_record.id)).to be true
        end
      end
    end

    context "when there's no applied record" do
      let(:issue) do
        {
          version: "20240116000006",
          migrations: [rolled_back_record, newest_record]
        }
      end

      it "keeps the most recent record" do
        expect(tracking_action).to receive(:log_success).with("✓ Removed 1 duplicate records")

        result = tracking_action.remove_duplicates(issue)

        aggregate_failures do
          expect(result).to be true
          expect(MigrationGuard::MigrationGuardRecord.exists?(rolled_back_record.id)).to be false
          expect(MigrationGuard::MigrationGuardRecord.exists?(newest_record.id)).to be true
        end
      end
    end

    context "when removal fails" do
      it "returns false and logs error" do
        allow(tracking_action).to receive(:perform_duplicate_removal).and_raise(StandardError, "Database error")
        expect(tracking_action).to receive(:log_error).with("✗ Failed to remove duplicates: Database error")

        issue = { version: "test", migrations: [] }
        result = tracking_action.remove_duplicates(issue)
        expect(result).to be false
      end
    end
  end

  describe "private methods" do
    describe "#find_keeper_record" do
      it "prefers applied records" do
        applied = MigrationGuard::MigrationGuardRecord.create!(
          version: "20240116000010",
          status: "applied",
          updated_at: 2.hours.ago
        )
        rolled_back = MigrationGuard::MigrationGuardRecord.create!(
          version: "20240116000011",
          status: "rolled_back",
          updated_at: 1.hour.ago
        )

        records = [rolled_back, applied]
        result = tracking_action.send(:find_keeper_record, records)

        expect(result).to eq(applied)
      end

      it "falls back to most recent when no applied records" do
        old = MigrationGuard::MigrationGuardRecord.create!(
          version: "20240116000008",
          status: "rolled_back",
          updated_at: 2.hours.ago
        )
        new = MigrationGuard::MigrationGuardRecord.create!(
          version: "20240116000009",
          status: "rolled_back",
          updated_at: 1.hour.ago
        )

        records = MigrationGuard::MigrationGuardRecord.where(id: [old.id, new.id])

        result = tracking_action.send(:find_keeper_record, records)
        expect(result.id).to eq(new.id)
      end
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
