# frozen_string_literal: true

require "rails_helper"

# rubocop:disable RSpec/SpecFilePathFormat
RSpec.describe MigrationGuard::Diagnostics::MigrationStateChecker, "#check_missing_migration_files" do
  # rubocop:enable RSpec/SpecFilePathFormat
  let(:issues) { [] }
  let(:warnings) { [] }
  let(:io) { StringIO.new }
  let(:reporter) { instance_double(MigrationGuard::Reporter, orphaned_migrations: [], missing_migrations: {}) }
  let(:checker) do
    described_class.new(issues: issues, warnings: warnings, output: io, reporter: reporter)
  end

  before do
    allow(MigrationGuard::Colorizer).to receive(:colorize_output?).and_return(false)

    # Create migration directory
    FileUtils.mkdir_p("db/migrate")
  end

  after do
    # Clean up any test files
    FileUtils.rm_rf(Dir.glob("db/migrate/*.rb"))
  end

  context "when all migration files exist" do
    before do
      # Create migration records
      MigrationGuard::MigrationGuardRecord.create!(
        version: "20240101000001",
        status: "applied",
        branch: "main"
      )

      # Create corresponding migration file
      File.write("db/migrate/20240101000001_test_migration.rb", <<~RUBY)
        class TestMigration < ActiveRecord::Migration[7.0]
          def change
            create_table :test_table
          end
        end
      RUBY
    end

    it "reports no missing files" do
      checker.run_checks

      output = io.string
      expect(output).to include("Migration files")
      expect(output).to include("all files present")
    end
  end

  context "when migration files are missing" do
    before do
      # Create migration records without corresponding files
      MigrationGuard::MigrationGuardRecord.create!(
        version: "20240101000001",
        status: "applied",
        branch: "main"
      )

      MigrationGuard::MigrationGuardRecord.create!(
        version: "20240102000002",
        status: "rolled_back",
        branch: "feature/test"
      )

      # Only create one file
      File.write("db/migrate/20240102000002_existing_migration.rb", <<~RUBY)
        class ExistingMigration < ActiveRecord::Migration[7.0]
          def change
          end
        end
      RUBY
    end

    it "reports missing migration files" do
      checker.run_checks

      file_issue = issues.find { |title, _| title == "Migration file(s) missing" }

      aggregate_failures do
        expect(io.string).to include("Migration files")
        expect(io.string).to include("1 missing")
        expect(file_issue).not_to be_nil
        expect(file_issue[1]).to include("20240101000001")
      end
    end

    it "includes migration versions in the issue description" do
      checker.run_checks

      file_issue = issues.find { |title, _| title == "Migration file(s) missing" }
      expect(file_issue[1]).to include("Cannot rollback migrations without their files: 20240101000001")
    end
  end

  context "when multiple migration files are missing" do
    before do
      # Create multiple migration records without files
      %w[20240101000001 20240102000002 20240103000003].each do |version|
        MigrationGuard::MigrationGuardRecord.create!(
          version: version,
          status: "applied",
          branch: "main"
        )
      end
    end

    it "reports all missing files" do
      checker.run_checks

      output = io.string
      file_issue = issues.find { |title, _| title == "Migration file(s) missing" }

      aggregate_failures do
        expect(output).to include("Migration files")
        expect(output).to include("3 missing")
        expect(file_issue[1]).to include("20240101000001")
        expect(file_issue[1]).to include("20240102000002")
        expect(file_issue[1]).to include("20240103000003")
      end
    end
  end

  context "when migration paths are configured" do
    before do
      allow(Rails.application.config).to receive(:paths).and_return({
                                                                      "db/migrate" => ["db/migrate",
                                                                                       "db/secondary_migrate"]
                                                                    })

      FileUtils.mkdir_p("db/secondary_migrate")

      # Create record
      MigrationGuard::MigrationGuardRecord.create!(
        version: "20240101000001",
        status: "applied",
        branch: "main"
      )

      # Put file in secondary path
      File.write("db/secondary_migrate/20240101000001_secondary.rb", <<~RUBY)
        class Secondary < ActiveRecord::Migration[7.0]
          def change
          end
        end
      RUBY
    end

    after do
      FileUtils.rm_rf("db/secondary_migrate")
    end

    it "checks all configured migration paths" do
      checker.run_checks

      output = io.string
      expect(output).to include("Migration files")
      expect(output).to include("all files present")
    end
  end
end
