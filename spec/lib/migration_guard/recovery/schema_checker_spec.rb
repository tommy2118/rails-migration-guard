# frozen_string_literal: true

require "rails_helper"

# rubocop:disable RSpec/IndexedLet, RSpec/LetSetup

RSpec.describe MigrationGuard::Recovery::SchemaChecker do
  let(:checker) { described_class.new }

  before do
    # Clear existing data
    MigrationGuard::MigrationGuardRecord.delete_all
    ActiveRecord::Base.connection.execute("DELETE FROM schema_migrations")
    # Mock time for consistent tests
    allow(Time).to receive(:current).and_return(Time.zone.parse("2024-01-16 12:00:00"))
  end

  describe "#check" do
    context "when schema and tracking are in sync" do
      before do
        # Create migration record
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240116000001",
          status: "applied",
          metadata: {}
        )

        # Add to schema
        ActiveRecord::Base.connection.execute(
          ActiveRecord::Base.sanitize_sql(
            ["INSERT INTO schema_migrations (version) VALUES (?)", "20240116000001"]
          )
        )
      end

      it "returns empty array" do
        issues = checker.check
        expect(issues).to be_empty
      end
    end

    context "when schema contains untracked migrations" do
      before do
        # Add migrations to schema without tracking
        ActiveRecord::Base.connection.execute(
          ActiveRecord::Base.sanitize_sql(
            ["INSERT INTO schema_migrations (version) VALUES (?)", "20240116000001"]
          )
        )
        ActiveRecord::Base.connection.execute(
          ActiveRecord::Base.sanitize_sql(
            ["INSERT INTO schema_migrations (version) VALUES (?)", "20240116000002"]
          )
        )
      end

      it "detects orphaned schema entries" do
        issues = checker.check

        orphaned_issues = issues.select { |i| i[:type] == :orphaned_schema }

        aggregate_failures do
          expect(orphaned_issues.size).to eq(2)

          versions = orphaned_issues.map { |i| i[:version] }
          expect(versions).to contain_exactly("20240116000001", "20240116000002")

          orphaned_issues.each do |issue|
            expect(issue[:description]).to eq("Schema contains migration not tracked by Migration Guard")
            expect(issue[:severity]).to eq(:medium)
            expect(issue[:recovery_options]).to include(:track_migration, :remove_from_schema)
          end
        end
      end
    end

    context "when tracking contains migrations missing from schema" do
      let!(:applied_migration1) do
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240116000001",
          status: "applied",
          branch: "main",
          metadata: {}
        )
      end

      let!(:applied_migration2) do
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240116000002",
          status: "applied",
          branch: "feature/test",
          metadata: {}
        )
      end

      it "detects missing schema entries" do
        issues = checker.check

        missing_issues = issues.select { |i| i[:type] == :missing_from_schema }

        aggregate_failures do
          expect(missing_issues.size).to eq(2)

          versions = missing_issues.map { |i| i[:version] }
          expect(versions).to contain_exactly("20240116000001", "20240116000002")

          missing_issues.each do |issue|
            expect(issue[:description]).to eq("Migration tracked as applied but missing from schema")
            expect(issue[:severity]).to eq(:high)
            expect(issue[:recovery_options]).to include(:reapply_migration, :mark_as_rolled_back)
            expect(issue[:migration]).to be_present
          end
        end
      end
    end

    context "when there are mixed issues" do
      before do
        # Create tracking record that's in schema (synced)
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240116000001",
          status: "applied",
          metadata: {}
        )
        ActiveRecord::Base.connection.execute(
          ActiveRecord::Base.sanitize_sql(
            ["INSERT INTO schema_migrations (version) VALUES (?)", "20240116000001"]
          )
        )

        # Create orphaned schema entry (no tracking)
        ActiveRecord::Base.connection.execute(
          ActiveRecord::Base.sanitize_sql(
            ["INSERT INTO schema_migrations (version) VALUES (?)", "20240116000002"]
          )
        )

        # Create tracking record missing from schema
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240116000003",
          status: "applied",
          metadata: {}
        )
      end

      it "detects both orphaned schema and missing schema issues" do
        issues = checker.check

        aggregate_failures do
          expect(issues.size).to eq(2)

          orphaned_issue = issues.find { |i| i[:type] == :orphaned_schema }
          expect(orphaned_issue[:version]).to eq("20240116000002")

          missing_issue = issues.find { |i| i[:type] == :missing_from_schema }
          expect(missing_issue[:version]).to eq("20240116000003")
        end
      end
    end

    context "when migrations have different statuses" do
      before do
        # Applied migration (should be checked for schema presence)
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240116000001",
          status: "applied",
          metadata: {}
        )

        # Rolled back migration (should not be checked for schema presence)
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240116000002",
          status: "rolled_back",
          metadata: {}
        )

        # Rolling back migration (should not be checked for schema presence)
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240116000003",
          status: "rolling_back",
          metadata: {}
        )

        # No schema entries exist
      end

      it "only checks applied migrations for schema presence" do
        issues = checker.check

        missing_issues = issues.select { |i| i[:type] == :missing_from_schema }

        aggregate_failures do
          expect(missing_issues.size).to eq(1)
          expect(missing_issues.first[:version]).to eq("20240116000001")
        end
      end
    end

    context "when schema and tracking are completely empty" do
      it "returns empty array" do
        issues = checker.check
        expect(issues).to be_empty
      end
    end

    context "when only schema has entries" do
      before do
        ActiveRecord::Base.connection.execute(
          ActiveRecord::Base.sanitize_sql(
            ["INSERT INTO schema_migrations (version) VALUES (?)", "20240116000001"]
          )
        )
      end

      it "detects all as orphaned" do
        issues = checker.check

        aggregate_failures do
          expect(issues.size).to eq(1)
          expect(issues.first[:type]).to eq(:orphaned_schema)
          expect(issues.first[:version]).to eq("20240116000001")
        end
      end
    end

    context "when only tracking has entries" do
      before do
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240116000001",
          status: "applied",
          metadata: {}
        )
      end

      it "detects all as missing from schema" do
        issues = checker.check

        aggregate_failures do
          expect(issues.size).to eq(1)
          expect(issues.first[:type]).to eq(:missing_from_schema)
          expect(issues.first[:version]).to eq("20240116000001")
        end
      end
    end
  end
end

# rubocop:enable RSpec/IndexedLet, RSpec/LetSetup
