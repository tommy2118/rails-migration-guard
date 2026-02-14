# frozen_string_literal: true

require "rails_helper"

RSpec.describe MigrationGuard::StatusPresenter do
  subject(:presenter) { described_class.new }

  before do
    allow(MigrationGuard::Colorizer).to receive(:colorize_output?).and_return(false)
  end

  describe "#format_status_output" do
    context "when all synced" do
      let(:report) do
        {
          current_branch: "feature/foo",
          main_branch: "main",
          synced_count: 5,
          orphaned_count: 0,
          missing_count: 0,
          orphaned_migrations: [],
          missing_migrations: []
        }
      end

      it "includes synced count and all-synced message" do
        result = presenter.format_status_output(report)

        aggregate_failures do
          expect(result).to include("5 migrations")
          expect(result).to include("All migrations synced with main")
        end
      end
    end

    context "when orphaned migrations exist" do
      let(:report) do
        {
          current_branch: "feature/foo",
          main_branch: "main",
          synced_count: 3,
          orphaned_count: 2,
          missing_count: 0,
          orphaned_migrations: [
            { version: "20240101000001", branch: "feature/old", author: "dev@example.com", age_in_days: 14 },
            { version: "20240102000002", branch: "feature/old", author: nil, age_in_days: 7 }
          ],
          missing_migrations: []
        }
      end

      it "includes orphaned details and rollback hint" do
        result = presenter.format_status_output(report)

        aggregate_failures do
          expect(result).to include("Orphaned")
          expect(result).to include("2 migrations")
          expect(result).to include("20240101000001")
          expect(result).to include("feature/old")
          expect(result).to include("dev@example.com")
          expect(result).to include("14 days")
          expect(result).to include("rollback_orphaned")
        end
      end
    end

    context "when missing migrations exist" do
      let(:report) do
        {
          current_branch: "feature/foo",
          main_branch: "main",
          synced_count: 3,
          orphaned_count: 0,
          missing_count: 2,
          orphaned_migrations: [],
          missing_migrations: %w[20240201000001 20240202000002]
        }
      end

      it "includes missing details and migrate hint" do
        result = presenter.format_status_output(report)

        aggregate_failures do
          expect(result).to include("Missing")
          expect(result).to include("20240201000001")
          expect(result).to include("20240202000002")
          expect(result).to include("rails db:migrate")
        end
      end
    end

    context "with multi-branch missing migrations" do
      let(:report) do
        {
          current_branch: "feature/foo",
          main_branch: "main",
          synced_count: 3,
          orphaned_count: 0,
          missing_count: 0,
          orphaned_migrations: [],
          missing_migrations: %w[20240301000001 20240302000002],
          target_branches: %w[main develop],
          missing_by_branch: {
            "main" => ["20240301000001"],
            "develop" => ["20240302000002"]
          }
        }
      end

      it "includes branch names in missing-by-branch section" do
        result = presenter.format_status_output(report)

        aggregate_failures do
          expect(result).to include("Missing Migrations by Branch")
          expect(result).to include("main")
          expect(result).to include("develop")
          expect(result).to include("20240301000001")
          expect(result).to include("20240302000002")
        end
      end
    end

    context "when sandbox mode is active" do
      let(:report) do
        {
          current_branch: "feature/foo",
          main_branch: "main",
          synced_count: 5,
          orphaned_count: 0,
          missing_count: 0,
          orphaned_migrations: [],
          missing_migrations: []
        }
      end

      it "includes sandbox warning" do
        allow(MigrationGuard.configuration).to receive(:sandbox_mode).and_return(true)

        result = presenter.format_status_output(report)

        expect(result).to include("SANDBOX MODE ACTIVE")
      end
    end
  end

  describe "#summary_line" do
    context "with orphaned migrations" do
      it "returns orphaned count and branch" do
        report = { orphaned_count: 2, current_branch: "feature/old", main_branch: "main" }

        result = presenter.summary_line(report)

        aggregate_failures do
          expect(result).to include("2 orphaned migrations")
          expect(result).to include("feature/old")
        end
      end

      it "uses singular for 1 migration" do
        report = { orphaned_count: 1, current_branch: "feature/old", main_branch: "main" }

        expect(presenter.summary_line(report)).to include("1 orphaned migration detected")
      end
    end

    context "with missing migrations on single branch" do
      it "returns missing count" do
        report = { orphaned_count: 0, missing_count: 3, main_branch: "main" }

        result = presenter.summary_line(report)

        aggregate_failures do
          expect(result).to include("3 missing migrations")
          expect(result).to include("main")
        end
      end
    end

    context "when all synced" do
      it "returns synced message" do
        report = { orphaned_count: 0, missing_count: 0, main_branch: "main" }

        expect(presenter.summary_line(report)).to include("All migrations synced with main")
      end
    end

    context "with multi-branch missing" do
      it "returns missing count with branch names" do
        report = {
          orphaned_count: 0,
          target_branches: %w[main develop],
          missing_migrations: %w[v1 v2],
          missing_by_branch: { "main" => ["v1"], "develop" => ["v2"] }
        }

        result = presenter.summary_line(report)

        aggregate_failures do
          expect(result).to include("2 missing migrations")
          expect(result).to include("main")
          expect(result).to include("develop")
        end
      end

      it "returns synced message when no missing" do
        report = {
          orphaned_count: 0,
          target_branches: %w[main develop],
          missing_by_branch: {}
        }

        expect(presenter.summary_line(report)).to include("All migrations synced with branches: main, develop")
      end
    end
  end
end
