# frozen_string_literal: true

require "rails_helper"

RSpec.describe MigrationGuard::Diagnostics::MigrationStateChecker do
  let(:issues) { [] }
  let(:warnings) { [] }
  let(:io) { StringIO.new }
  let(:reporter) { instance_double(MigrationGuard::Reporter) }
  let(:checker) do
    described_class.new(issues: issues, warnings: warnings, output: io, reporter: reporter)
  end

  before do
    allow(MigrationGuard::Colorizer).to receive(:colorize_output?).and_return(false)
    allow(reporter).to receive_messages(orphaned_migrations: [], missing_migrations: {})
  end

  describe "#run_checks" do
    describe "orphaned migrations" do
      context "when none exist" do
        it "reports success" do
          checker.run_checks

          expect(io.string).to include("Orphaned migrations: none found")
        end
      end

      context "when orphaned migrations exist" do
        before do
          orphaned = MigrationGuard::MigrationGuardRecord.new(version: "20240115123456", created_at: 3.days.ago)
          allow(reporter).to receive(:orphaned_migrations).and_return([orphaned])
        end

        it "adds an issue with count and age" do
          checker.run_checks

          aggregate_failures do
            expect(io.string).to include("1 found (oldest: 3 days)")
            expect(issues.flatten).to include("Orphaned migrations detected")
          end
        end
      end
    end

    describe "missing migrations" do
      context "when none exist" do
        it "reports success" do
          checker.run_checks

          expect(io.string).to include("Missing migrations: none found")
        end
      end

      context "when missing migrations exist" do
        before do
          allow(reporter).to receive(:missing_migrations).and_return(
            "main" => %w[20240101000001 20240102000002],
            "develop" => ["20240103000003"]
          )
        end

        it "adds a warning with count and branches" do
          checker.run_checks

          aggregate_failures do
            expect(io.string).to include("3 found in: main, develop")
            expect(warnings.flatten).to include("Missing migrations from trunk")
          end
        end
      end
    end

    describe "stuck migrations" do
      context "when none exist" do
        it "reports success" do
          checker.run_checks

          expect(io.string).to include("Stuck migrations: none found")
        end
      end

      context "when stuck migrations exist" do
        before do
          MigrationGuard::MigrationGuardRecord.create!(
            version: "20240201000002",
            status: "rolling_back",
            branch: "feature/stuck",
            updated_at: 20.minutes.ago
          )
        end

        it "reports stuck migrations with details" do
          checker.run_checks

          aggregate_failures do
            expect(io.string).to include("1 stuck (oldest: 20m)")
            expect(issues.flatten).to include("Stuck migrations detected")
            stuck_issue = issues.find { |title, _| title == "Stuck migrations detected" }
            expect(stuck_issue.last).to include("20240201000002")
          end
        end
      end

      context "with custom stuck_migration_timeout" do
        before do
          allow(MigrationGuard.configuration).to receive(:stuck_migration_timeout).and_return(5)

          MigrationGuard::MigrationGuardRecord.create!(
            version: "20240301000001",
            status: "rolling_back",
            branch: "feature/test",
            updated_at: 3.minutes.ago
          )

          MigrationGuard::MigrationGuardRecord.create!(
            version: "20240301000002",
            status: "rolling_back",
            branch: "feature/test",
            updated_at: 7.minutes.ago
          )
        end

        it "respects the configured timeout" do
          checker.run_checks

          stuck_issue = issues.find { |title, _| title == "Stuck migrations detected" }

          aggregate_failures do
            expect(io.string).to include("1 stuck")
            expect(stuck_issue.last).to include("20240301000002")
            expect(stuck_issue.last).not_to include("20240301000001")
          end
        end
      end
    end

    describe "schema consistency" do
      context "when consistent" do
        it "reports success" do
          checker.run_checks

          expect(io.string).to include("Schema consistency")
          expect(io.string).to include("schema_migrations in sync")
        end
      end

      context "when inconsistencies exist" do
        before do
          MigrationGuard::MigrationGuardRecord.create!(
            version: "20240101000001",
            status: "applied",
            branch: "main"
          )

          ActiveRecord::Base.connection.execute(
            "INSERT INTO schema_migrations (version) VALUES ('20240101000002')"
          )

          MigrationGuard::MigrationGuardRecord.create!(
            version: "20240101000003",
            status: "rolled_back",
            branch: "feature"
          )
          ActiveRecord::Base.connection.execute(
            "INSERT INTO schema_migrations (version) VALUES ('20240101000003')"
          )
        end

        after do
          ActiveRecord::Base.connection.execute(
            "DELETE FROM schema_migrations WHERE version IN ('20240101000002', '20240101000003')"
          )
        end

        it "reports all inconsistency types" do
          checker.run_checks

          aggregate_failures do
            expect(io.string).to include("1 tracked as applied but missing from schema")
            expect(io.string).to include("1 rolled back but still in schema")
            expect(io.string).to include("1 in schema but not tracked")
          end
        end
      end
    end

    describe "missing migration files" do
      context "when all files present" do
        it "reports success" do
          checker.run_checks

          expect(io.string).to include("Migration files")
          expect(io.string).to include("all files present")
        end
      end
    end
  end
end
