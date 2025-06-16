# frozen_string_literal: true

require "rails_helper"

# rubocop:disable RSpec/IndexedLet, RSpec/LetSetup

RSpec.describe MigrationGuard::Recovery::RollbackChecker do
  let(:checker) { described_class.new }

  before do
    # Clear existing data
    MigrationGuard::MigrationGuardRecord.delete_all
    # Mock time for consistent tests
    allow(Time).to receive(:current).and_return(Time.zone.parse("2024-01-16 12:00:00"))
  end

  describe "#check" do
    context "when no rolling_back migrations exist" do
      it "returns empty array" do
        # Create migrations with other statuses
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

        issues = checker.check
        expect(issues).to be_empty
      end
    end

    context "when rolling_back migrations are recent" do
      it "returns empty array" do
        # Create recent rolling_back migration (within timeout)
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240116000001",
          status: "rolling_back",
          branch: "feature/test",
          created_at: 30.minutes.ago,
          updated_at: 30.minutes.ago,
          metadata: {}
        )

        issues = checker.check
        expect(issues).to be_empty
      end
    end

    context "when rolling_back migrations are stuck" do
      let!(:stuck_migration) do
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240116000001",
          status: "rolling_back",
          branch: "feature/stuck",
          created_at: 2.hours.ago,
          updated_at: 2.hours.ago,
          metadata: { "started_at" => 2.hours.ago.iso8601 }
        )
      end

      it "detects stuck rollback" do
        issues = checker.check

        aggregate_failures do
          expect(issues.size).to eq(1)

          issue = issues.first
          expect(issue[:type]).to eq(:partial_rollback)
          expect(issue[:version]).to eq("20240116000001")
          expect(issue[:migration]).to eq(stuck_migration)
          expect(issue[:description]).to eq("Migration appears to be stuck in rollback state")
          expect(issue[:severity]).to eq(:high)
          expect(issue[:recovery_options]).to include(
            :complete_rollback, :restore_migration, :mark_as_rolled_back
          )
        end
      end
    end

    context "when multiple migrations are stuck" do
      let!(:stuck_migration1) do
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240116000001",
          status: "rolling_back",
          branch: "feature/stuck1",
          created_at: 2.hours.ago,
          updated_at: 2.hours.ago,
          metadata: {}
        )
      end

      let!(:stuck_migration2) do
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240116000002",
          status: "rolling_back",
          branch: "feature/stuck2",
          created_at: 3.hours.ago,
          updated_at: 3.hours.ago,
          metadata: {}
        )
      end

      it "detects all stuck rollbacks" do
        issues = checker.check

        aggregate_failures do
          expect(issues.size).to eq(2)

          versions = issues.map { |i| i[:version] }
          expect(versions).to contain_exactly("20240116000001", "20240116000002")

          issues.each do |issue|
            expect(issue[:type]).to eq(:partial_rollback)
            expect(issue[:severity]).to eq(:high)
          end
        end
      end
    end

    context "when mixing recent and stuck rollbacks" do
      before do
        # Recent rollback (should not be detected)
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240116000001",
          status: "rolling_back",
          branch: "feature/recent",
          created_at: 30.minutes.ago,
          updated_at: 30.minutes.ago,
          metadata: {}
        )

        # Stuck rollback (should be detected)
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240116000002",
          status: "rolling_back",
          branch: "feature/stuck",
          created_at: 2.hours.ago,
          updated_at: 2.hours.ago,
          metadata: {}
        )
      end

      it "only detects stuck rollbacks" do
        issues = checker.check

        aggregate_failures do
          expect(issues.size).to eq(1)
          expect(issues.first[:version]).to eq("20240116000002")
        end
      end
    end

    context "when rollback exactly at timeout boundary" do
      before do
        # Migration exactly at the timeout boundary (should be detected)
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240116000001",
          status: "rolling_back",
          branch: "feature/boundary",
          created_at: 1.hour.ago,
          updated_at: 1.hour.ago,
          metadata: {}
        )
      end

      it "detects rollback at timeout boundary" do
        issues = checker.check

        aggregate_failures do
          expect(issues.size).to eq(1)
          expect(issues.first[:version]).to eq("20240116000001")
        end
      end
    end

    describe "ROLLBACK_TIMEOUT constant" do
      it "is set to 1 hour" do
        expect(described_class::ROLLBACK_TIMEOUT).to eq(1.hour)
      end
    end
  end
end

# rubocop:enable RSpec/IndexedLet, RSpec/LetSetup
