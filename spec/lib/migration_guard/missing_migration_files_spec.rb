# frozen_string_literal: true

require "rails_helper"

# rubocop:disable RSpec/SpecFilePathFormat
RSpec.describe MigrationGuard::DiagnosticRunner, "#check_missing_migration_files" do
  # rubocop:enable RSpec/SpecFilePathFormat
  let(:runner) { described_class.new }
  let(:io) { StringIO.new }

  before do
    allow(MigrationGuard::Colorizer).to receive(:colorize_output?).and_return(false)
    allow(runner).to receive(:puts) { |msg| io.puts(msg) }

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
      runner.send(:check_missing_migration_files)

      output = io.string
      expect(output).to include("✓ Migration files")
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
      runner.send(:check_missing_migration_files)

      output = io.string
      expect(output).to include("✗ Migration files")
      expect(output).to include("1 missing")

      # Check that issue was added (details are in the issues array)
      issues = runner.instance_variable_get(:@issues)
      expect(issues).not_to be_empty
      expect(issues.first[0]).to eq("Migration file(s) missing")
      expect(issues.first[1]).to include("20240101000001")
    end

    it "includes migration versions in the issue description" do
      runner.send(:check_missing_migration_files)

      # Check that the issue description includes the version
      issues = runner.instance_variable_get(:@issues)
      expect(issues.first[1]).to include("Cannot rollback migrations without their files: 20240101000001")
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
      runner.send(:check_missing_migration_files)

      output = io.string
      expect(output).to include("✗ Migration files")
      expect(output).to include("3 missing")

      # Check that issue includes all versions
      issues = runner.instance_variable_get(:@issues)
      issue_description = issues.first[1]
      expect(issue_description).to include("20240101000001")
      expect(issue_description).to include("20240102000002")
      expect(issue_description).to include("20240103000003")
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
      runner.send(:check_missing_migration_files)

      output = io.string
      expect(output).to include("✓ Migration files")
      expect(output).to include("all files present")
    end
  end
end
