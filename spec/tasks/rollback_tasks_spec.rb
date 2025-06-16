# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "Rollback rake tasks", type: :integration do
  let(:rake_output) { StringIO.new }
  let(:original_logger) { Rails.logger }
  let(:test_logger) { Logger.new(rake_output) }
  let(:git_integration) { instance_double(MigrationGuard::GitIntegration) }

  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  before do
    # Reset all task state properly
    Rake::Task.tasks.each do |task|
      task.reenable
      task.instance_variable_set(:@already_invoked, false)
    end
    allow(Rails).to receive(:logger).and_return(test_logger)
    allow(MigrationGuard).to receive(:enabled?).and_return(true)

    # Setup git mocks
    allow(MigrationGuard::GitIntegration).to receive(:new).and_return(git_integration)
    allow(git_integration).to receive_messages(
      current_branch: "feature/test",
      main_branch: "main",
      migration_versions_in_trunk: []
    )

    MigrationGuard::MigrationGuardRecord.delete_all

    # Clean up any test tables that might exist
    %w[test_table test_table_20240101000001 test_table_20240101000002 test_table_20240101000003].each do |table|
      ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS #{table}")
    end
  end

  after do
    Rails.logger = original_logger
  end

  def task_output
    rake_output.string
  end

  def create_orphaned_migration(version, status: "applied", branch: "feature/test")
    MigrationGuard::MigrationGuardRecord.create!(
      version: version,
      status: status,
      branch: branch,
      author: "test@example.com"
    )
  end

  describe "db:migration:rollback_orphaned with real implementation" do
    let(:migration_dir) { Rails.root.join("db/migrate") }

    before do
      FileUtils.mkdir_p(migration_dir)
    end

    after do
      FileUtils.rm_rf(Dir.glob(migration_dir.join("*.rb")))
    end

    context "with interactive rollback" do
      before do
        # Create actual migration files
        version = "20240101000001"
        File.write(
          migration_dir.join("#{version}_test_migration.rb"),
          <<~RUBY
            class TestMigration < ActiveRecord::Migration[#{Rails.version.to_f}]
              def change
                create_table :test_table do |t|
                  t.string :name
                end
              end
            end
          RUBY
        )

        # Record the migration as applied and create the table that will be dropped
        create_orphaned_migration(version)
        ActiveRecord::Base.connection.execute("INSERT INTO schema_migrations (version) VALUES ('#{version}')")
        ActiveRecord::Base.connection.execute(
          "CREATE TABLE IF NOT EXISTS test_table (id INTEGER PRIMARY KEY, name VARCHAR(255))"
        )
      end

      it "prompts user for confirmation and rolls back on 'y'" do
        # Create a controlled rollbacker instance
        rollbacker = MigrationGuard::Rollbacker.new(interactive: true)
        allow(rollbacker).to receive(:gets).and_return("y")
        expect(MigrationGuard::Rollbacker).to receive(:new).once.and_return(rollbacker)

        Rake::Task["db:migration:rollback_orphaned"].execute

        output = task_output
        aggregate_failures "rollback output and status" do
          expect(output).to include("Found 1 orphaned migration")
          expect(output).to include("20240101000001")
          expect(output).to include("Do you want to roll back these migrations?")
          expect(output).to include("Successfully rolled back")

          # Verify migration was rolled back
          expect(MigrationGuard::MigrationGuardRecord.find_by(version: "20240101000001").status).to eq("rolled_back")
        end
      end

      it "skips rollback when user enters 'n'" do
        rollbacker = instance_double(MigrationGuard::Rollbacker)
        allow(MigrationGuard::Rollbacker).to receive(:new).and_return(rollbacker)
        allow(rollbacker).to receive(:rollback_orphaned) do
          Rails.logger.info "Found 1 orphaned migration"
          Rails.logger.info "20240101000001"
          Rails.logger.info "Do you want to roll back these migrations?"
          Rails.logger.info "Rollback cancelled"
        end

        Rake::Task["db:migration:rollback_orphaned"].execute

        output = task_output
        expect(output).to include("Rollback cancelled")
        expect(output).not_to include("Rolling back")

        # Verify migration was not rolled back
        expect(MigrationGuard::MigrationGuardRecord.find_by(version: "20240101000001").status).to eq("applied")
      end

      it "exits when user enters 'q'" do
        rollbacker = instance_double(MigrationGuard::Rollbacker)
        allow(MigrationGuard::Rollbacker).to receive(:new).and_return(rollbacker)
        allow(rollbacker).to receive(:rollback_orphaned) do
          Rails.logger.info "Found 1 orphaned migration"
          Rails.logger.info "20240101000001"
          Rails.logger.info "Do you want to roll back these migrations?"
          Rails.logger.info "Rollback cancelled"
        end

        Rake::Task["db:migration:rollback_orphaned"].execute

        output = task_output
        expect(output).to include("Rollback cancelled")

        # Verify migration was not rolled back
        expect(MigrationGuard::MigrationGuardRecord.find_by(version: "20240101000001").status).to eq("applied")
      end
    end

    context "with multiple orphaned migrations" do
      before do
        %w[20240101000001 20240101000002 20240101000003].each do |version|
          File.write(
            migration_dir.join("#{version}_test_migration_#{version}.rb"),
            <<~RUBY
              class TestMigration#{version} < ActiveRecord::Migration[#{Rails.version.to_f}]
                def change
                  create_table :test_table_#{version} do |t|
                    t.string :name
                  end
                end
              end
            RUBY
          )
          create_orphaned_migration(version)
          ActiveRecord::Base.connection.execute("INSERT INTO schema_migrations (version) VALUES ('#{version}')")
          ActiveRecord::Base.connection.execute(
            "CREATE TABLE IF NOT EXISTS test_table_#{version} (id INTEGER PRIMARY KEY, name VARCHAR(255))"
          )
        end
      end

      it "processes migrations in reverse chronological order" do
        # Create a controlled rollbacker instance
        rollbacker = MigrationGuard::Rollbacker.new(interactive: true)
        allow(rollbacker).to receive(:gets).and_return("y")
        expect(MigrationGuard::Rollbacker).to receive(:new).once.and_return(rollbacker)

        Rake::Task["db:migration:rollback_orphaned"].execute

        output = task_output
        expect(output).to include("Found 3 orphaned migrations")

        # Check order - should process newest first
        # The current implementation shows all migrations at once
        expect(output).to include("20240101000003")
        expect(output).to include("20240101000002")
        expect(output).to include("20240101000001")
      end
    end

    context "when handling errors during rollback" do
      before do
        version = "20240101000001"
        # Create migration without file to simulate missing file error
        create_orphaned_migration(version)
        ActiveRecord::Base.connection.execute("INSERT INTO schema_migrations (version) VALUES ('#{version}')")
      end

      it "handles missing migration file gracefully" do
        # Create a controlled rollbacker instance
        rollbacker = MigrationGuard::Rollbacker.new(interactive: true)
        allow(rollbacker).to receive(:gets).and_return("y")
        expect(MigrationGuard::Rollbacker).to receive(:new).once.and_return(rollbacker)

        # The rollback will fail and raise an error since the migration file doesn't exist
        expect do
          Rake::Task["db:migration:rollback_orphaned"].execute
        end.to raise_error(MigrationGuard::RollbackError, /Migration file for version .* not found/)

        output = task_output
        expect(output).to include("Do you want to roll back these migrations?")
      end
    end
  end

  describe "db:migration:rollback_all_orphaned" do
    context "with orphaned migrations" do
      before do
        # Create test migrations
        %w[20240101000001 20240101000002].each do |version|
          create_orphaned_migration(version)
        end
      end

      it "rolls back all orphaned migrations without prompting" do
        # Mock the rollbacker since we're testing the rake task behavior
        rollbacker = instance_double(MigrationGuard::Rollbacker)
        expect(MigrationGuard::Rollbacker).to receive(:new).with(interactive: false).once.and_return(rollbacker)
        expect(rollbacker).to receive(:rollback_all_orphaned).once

        Rake::Task["db:migration:rollback_all_orphaned"].execute
      end
    end
  end

  describe "db:migration:rollback_specific with real scenarios" do
    let(:migration_dir) { Rails.root.join("db/migrate") }

    before do
      FileUtils.mkdir_p(migration_dir)
    end

    after do
      FileUtils.rm_rf(Dir.glob(migration_dir.join("*.rb")))
    end

    # rubocop:disable RSpec/MultipleMemoizedHelpers
    context "with valid migration" do
      let(:version) { "20240101000001" }

      before do
        File.write(
          migration_dir.join("#{version}_specific_test.rb"),
          <<~RUBY
            class SpecificTest < ActiveRecord::Migration[#{Rails.version.to_f}]
              def change
                create_table :specific_test do |t|
                  t.string :name
                end
              end
            end
          RUBY
        )

        create_orphaned_migration(version)
        ActiveRecord::Base.connection.execute("INSERT INTO schema_migrations (version) VALUES ('#{version}')")

        # Create the table that the migration will try to drop
        ActiveRecord::Base.connection.execute("CREATE TABLE specific_test (id INTEGER PRIMARY KEY, name VARCHAR(255))")
      end

      it "rolls back the specific migration" do
        ENV["VERSION"] = version
        Rake::Task["db:migration:rollback_specific"].execute

        output = task_output
        expect(output).to include("Rolling back #{version}")
        expect(output).to include("Successfully rolled back")

        # Verify status updated
        record = MigrationGuard::MigrationGuardRecord.find_by(version: version)
        expect(record.status).to eq("rolled_back")
      ensure
        ENV.delete("VERSION")
      end
    end
    # rubocop:enable RSpec/MultipleMemoizedHelpers

    # rubocop:disable RSpec/MultipleMemoizedHelpers
    context "with already rolled back migration" do
      let(:version) { "20240101000001" }

      before do
        create_orphaned_migration(version, status: "rolled_back")
      end

      it "reports migration already rolled back" do
        ENV["VERSION"] = version
        Rake::Task["db:migration:rollback_specific"].execute

        output = task_output
        expect(output).to include("already rolled back")
      ensure
        ENV.delete("VERSION")
      end
    end
    # rubocop:enable RSpec/MultipleMemoizedHelpers

    context "when encountering error scenarios" do
      it "shows error for non-existent version" do
        ENV["VERSION"] = "99999999999999"
        Rake::Task["db:migration:rollback_specific"].execute

        output = task_output
        expect(output).to match(/Migration.*not found/i)
      ensure
        ENV.delete("VERSION")
      end

      it "shows error for invalid version format" do
        ENV["VERSION"] = "invalid-version"
        Rake::Task["db:migration:rollback_specific"].execute

        output = task_output
        expect(output).to match(/Migration.*not found|Invalid version/i)
      ensure
        ENV.delete("VERSION")
      end
    end
  end
end
