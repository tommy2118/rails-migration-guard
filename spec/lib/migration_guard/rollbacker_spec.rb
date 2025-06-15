# frozen_string_literal: true

require "rails_helper"

# Mock ActiveRecord::Migration for testing
unless defined?(ActiveRecord::Migration.execute_down)
  module ActiveRecord
    class Migration
      def self.execute_down(version)
        # Mock implementation
      end
    end
  end
end

RSpec.describe MigrationGuard::Rollbacker do
  before do
    # Disable colorization for testing
    allow(MigrationGuard::Colorizer).to receive(:colorize_output?).and_return(false)
    allow(MigrationGuard::GitIntegration).to receive(:new).and_return(git_integration)
    allow(git_integration).to receive_messages(
      main_branch: "main",
      migration_versions_in_trunk: ["20240101000001"]
    )
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
          allow(ActiveRecord::Migration).to receive(:execute_down)
        end

        it "rolls back the migration" do
          rollbacker.rollback_orphaned

          expect(ActiveRecord::Migration).to have_received(:execute_down).with("20240102000002")
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
          allow(ActiveRecord::Migration).to receive(:execute_down)
        end

        it "does not roll back the migration" do
          rollbacker.rollback_orphaned

          expect(ActiveRecord::Migration).not_to have_received(:execute_down)
        end

        it "displays cancellation message" do
          rollbacker.rollback_orphaned

          expect(io.string).to include("Rollback cancelled")
        end
      end

      context "when rollback fails" do
        before do
          allow(rollbacker).to receive(:gets).and_return("y\n")
          allow(ActiveRecord::Migration).to receive(:execute_down).and_raise(StandardError, "Migration error")
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
        allow(ActiveRecord::Migration).to receive(:execute_down)
        allow(rollbacker).to receive(:gets)
      end

      it "rolls back without confirmation" do
        rollbacker.rollback_orphaned

        expect(ActiveRecord::Migration).to have_received(:execute_down).with("20240102000002")
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
        allow(ActiveRecord::Migration).to receive(:execute_down)
      end

      it "rolls back the specific migration" do
        rollbacker.rollback_specific("20240102000002")

        expect(ActiveRecord::Migration).to have_received(:execute_down).with("20240102000002")
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
        allow(ActiveRecord::Migration).to receive(:execute_down)

        rollbacker.rollback_specific("20240102000002")

        expect(ActiveRecord::Migration).not_to have_received(:execute_down)
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
        allow(ActiveRecord::Migration).to receive(:execute_down)
      end

      it "rolls back all orphaned migrations" do
        rollbacker.rollback_all_orphaned

        expect(ActiveRecord::Migration).to have_received(:execute_down).with("20240102000002")
        expect(ActiveRecord::Migration).to have_received(:execute_down).with("20240103000003")
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
        allow(ActiveRecord::Migration).to receive(:execute_down).with("20240102000002")
        allow(ActiveRecord::Migration).to receive(:execute_down).with("20240103000003")
                                                                .and_raise(StandardError, "Migration error")
      end

      it "continues with other migrations" do
        rollbacker.rollback_all_orphaned

        expect(ActiveRecord::Migration).to have_received(:execute_down).with("20240102000002")
      end

      it "reports partial success" do
        rollbacker.rollback_all_orphaned

        output = io.string
        aggregate_failures do
          expect(output).to include("Failed to roll back 20240103000003:")
          expect(output).to include("Migration error")
          expect(output).to include("Rolled back 1 migration(s) with 1 failure(s)")
        end
      end
    end
  end
end
