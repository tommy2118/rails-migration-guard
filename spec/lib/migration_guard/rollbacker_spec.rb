# frozen_string_literal: true

require "rails_helper"

# Helper methods for mocking migration rollback
module RollbackSpecHelpers
  # rubocop:disable Metrics/AbcSize
  def setup_migration_context_mocks(versions = [20_240_102_000_002, 20_240_103_000_003])
    @mock_context = instance_double(ActiveRecord::MigrationContext)
    @mock_migrations = {}

    # Create mock migrations for each version
    versions.each do |version|
      mock_migration = instance_double(ActiveRecord::Migration)
      allow(mock_migration).to receive(:version).and_return(version)
      allow(mock_migration).to receive(:migrate)
      @mock_migrations[version] = mock_migration
    end

    if defined?(Rails) && Rails.respond_to?(:application)
      allow(Rails.application.config).to receive(:paths).and_return({ "db/migrate" => ["db/migrate"] })
    end
    allow(ActiveRecord::MigrationContext).to receive(:new).and_return(@mock_context)
    allow(@mock_context).to receive_messages(get_all_versions: versions, migrations: @mock_migrations.values)
  end
  # rubocop:enable Metrics/AbcSize

  def expect_migration_rollback(version)
    version_int = version.to_i
    migration = @mock_migrations[version_int]
    expect(migration).to have_received(:migrate).with(:down) if migration
  end

  def expect_no_migration_rollback
    @mock_migrations.each_value do |migration|
      expect(migration).not_to have_received(:migrate)
    end
  end

  def simulate_rollback_error(error_message = "Migration error", version = nil)
    if version
      migration = @mock_migrations[version.to_i]
      allow(migration).to receive(:migrate).and_raise(StandardError, error_message) if migration
    else
      @mock_migrations.values.first&.tap do |migration|
        allow(migration).to receive(:migrate).and_raise(StandardError, error_message)
      end
    end
  end

  def simulate_missing_migration(version)
    version_int = version.to_i
    # Remove the migration from the context but keep it in applied versions
    @mock_migrations.delete(version_int)
    allow(@mock_context).to receive(:migrations).and_return(@mock_migrations.values)
  end
end

RSpec.describe MigrationGuard::Rollbacker do
  include RollbackSpecHelpers

  before do
    # Disable colorization for testing
    allow(MigrationGuard::Colorizer).to receive(:colorize_output?).and_return(false)
    allow(MigrationGuard::GitIntegration).to receive(:new).and_return(git_integration)
    allow(git_integration).to receive_messages(
      main_branch: "main",
      migration_versions_in_trunk: ["20240101000001"]
    )
    # Capture stdout output from puts
    allow($stdout).to receive(:puts) { |msg| io.puts(msg) }
    # Also capture Rails.logger for Logger messages
    allow(Rails.logger).to receive(:debug) do |*args, &block|
      message = if block
                  block.call
                else
                  args.first
                end
      io.puts(message) if message
    end
    allow(Rails.logger).to receive(:info) { |msg| io.puts(msg) }
    allow(Rails.logger).to receive(:error) { |msg| io.puts(msg) }
    allow(rollbacker).to receive(:print) { |msg| io.print(msg) }
  end

  let(:rollbacker) { described_class.new }
  let(:git_integration) { instance_double(MigrationGuard::GitIntegration) }
  let(:io) { StringIO.new }

  describe "#rollback_orphaned" do
    context "with orphaned migrations" do
      let!(:orphaned_migration) do
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240102000002",
          status: "applied",
          branch: "feature/test"
        )
      end

      context "when user confirms rollback" do
        before do
          allow(rollbacker).to receive(:gets).and_return("y\n")
          setup_migration_context_mocks
        end

        it "rolls back the migration" do
          rollbacker.rollback_orphaned

          expect_migration_rollback("20240102000002")
        end

        it "updates the migration record status" do
          rollbacker.rollback_orphaned

          orphaned_migration.reload
          expect(orphaned_migration.status).to eq("rolled_back")
        end

        it "displays rollback progress" do
          rollbacker.rollback_orphaned

          output = io.string
          aggregate_failures do
            expect(output).to include("Found 1 orphaned migration")
            expect(output).to include("20240102000002")
            expect(output).to include("Do you want to roll back")
            expect(output).to include("Rolling back 20240102000002...")
            expect(output).to include("✓ Successfully rolled back")
          end
        end
      end

      context "when user declines rollback" do
        before do
          allow(rollbacker).to receive(:gets).and_return("n\n")
          setup_migration_context_mocks
        end

        it "does not roll back the migration" do
          rollbacker.rollback_orphaned

          expect_no_migration_rollback
        end

        it "displays cancellation message" do
          rollbacker.rollback_orphaned

          expect(io.string).to include("Rollback cancelled")
        end
      end

      context "when rollback fails" do
        before do
          allow(rollbacker).to receive(:gets).and_return("y\n")
          setup_migration_context_mocks
          simulate_rollback_error("Migration error")
        end

        it "raises RollbackError" do
          expect { rollbacker.rollback_orphaned }.to raise_error(MigrationGuard::RollbackError)
        end

        it "does not update the record status" do
          expect { rollbacker.rollback_orphaned }.to raise_error(MigrationGuard::RollbackError)

          orphaned_migration.reload
          expect(orphaned_migration.status).to eq("applied")
        end
      end
    end

    context "with no orphaned migrations" do
      it "displays no orphaned migrations message" do
        rollbacker.rollback_orphaned

        expect(io.string).to include("No orphaned migrations found")
      end
    end

    context "with interactive mode disabled" do
      let(:rollbacker) { described_class.new(interactive: false) }

      let(:orphaned_migration) do
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240102000002",
          status: "applied",
          branch: "feature/test"
        )
      end

      before do
        orphaned_migration
        setup_migration_context_mocks
        allow(rollbacker).to receive(:gets)
      end

      it "rolls back without confirmation" do
        rollbacker.rollback_orphaned

        expect_migration_rollback("20240102000002")
        expect(rollbacker).not_to have_received(:gets)
      end
    end
  end

  describe "#rollback_specific" do
    context "when migration exists" do
      let!(:migration) do
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240102000002",
          status: "applied",
          branch: "feature/test"
        )
      end

      before do
        setup_migration_context_mocks
      end

      it "rolls back the specific migration" do
        rollbacker.rollback_specific("20240102000002")

        expect_migration_rollback("20240102000002")
      end

      it "updates the migration status" do
        rollbacker.rollback_specific("20240102000002")

        migration.reload
        expect(migration.status).to eq("rolled_back")
      end

      it "displays success message" do
        rollbacker.rollback_specific("20240102000002")

        expect(io.string).to include("✓ Successfully rolled back 20240102000002")
      end
    end

    context "when migration doesn't exist" do
      it "raises MigrationNotFoundError" do
        expect { rollbacker.rollback_specific("99999999999999") }
          .to raise_error(MigrationGuard::MigrationNotFoundError)
      end
    end

    context "when migration is already rolled back" do
      let(:migration) do
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240102000002",
          status: "rolled_back",
          branch: "feature/test"
        )
      end

      before { migration }

      it "displays already rolled back message" do
        rollbacker.rollback_specific("20240102000002")

        expect(io.string).to include("Migration 20240102000002 is already rolled back")
      end

      it "does not execute rollback" do
        setup_migration_context_mocks

        rollbacker.rollback_specific("20240102000002")

        expect_no_migration_rollback
      end
    end
  end

  describe "#rollback_all_orphaned" do
    let!(:orphaned_migrations) do
      [
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240102000002",
          status: "applied",
          branch: "feature/test1"
        ),
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240103000003",
          status: "applied",
          branch: "feature/test2"
        )
      ]
    end

    context "when user confirms" do
      before do
        allow(rollbacker).to receive(:gets).and_return("y\n")
        setup_migration_context_mocks
      end

      it "rolls back all orphaned migrations" do
        rollbacker.rollback_all_orphaned

        expect_migration_rollback("20240102000002")
        expect_migration_rollback("20240103000003")
      end

      it "updates all migration statuses" do
        rollbacker.rollback_all_orphaned

        orphaned_migrations.each do |migration|
          migration.reload
          expect(migration.status).to eq("rolled_back")
        end
      end

      it "displays progress for each migration" do
        rollbacker.rollback_all_orphaned

        output = io.string
        aggregate_failures do
          expect(output).to include("Found 2 orphaned migrations")
          expect(output).to include("Rolling back 20240102000002...")
          expect(output).to include("Rolling back 20240103000003...")
          expect(output).to include("✓ All orphaned migrations rolled back successfully")
        end
      end
    end

    context "when one rollback fails" do
      before do
        allow(rollbacker).to receive(:gets).and_return("y\n")
        setup_migration_context_mocks
        simulate_missing_migration(20_240_103_000_003)
      end

      it "continues with other migrations" do
        rollbacker.rollback_all_orphaned

        expect_migration_rollback("20240102000002")
      end

      it "reports partial success" do
        rollbacker.rollback_all_orphaned

        output = io.string
        aggregate_failures do
          expect(output).to include("Failed to roll back 20240103000003:")
          expect(output).to include("Migration file for version 20240103000003 not found")
          expect(output).to include("Rolled back 1 migration(s) with 1 failure(s)")
        end
      end
    end
  end
end
