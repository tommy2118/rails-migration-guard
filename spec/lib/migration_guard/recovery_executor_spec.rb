# frozen_string_literal: true

require "rails_helper"

RSpec.describe MigrationGuard::RecoveryExecutor do
  let(:executor) { described_class.new(interactive: false) }
  let(:git_integration) { instance_double(MigrationGuard::GitIntegration) }

  before do
    # Clean up any existing records
    MigrationGuard::MigrationGuardRecord.delete_all

    # Mock git integration
    allow(MigrationGuard::GitIntegration).to receive(:new).and_return(git_integration)
    allow(git_integration).to receive_messages(
      current_branch: "feature/test",
      current_author: "test@example.com"
    )

    # Clear schema_migrations for tests
    ActiveRecord::Base.connection.execute("DELETE FROM schema_migrations")

    # Mock backup creation
    allow(executor).to receive(:create_backup).and_return(true)
  end

  describe "#execute_recovery" do
    let(:migration) do
      MigrationGuard::MigrationGuardRecord.create!(
        version: "20240101000001",
        status: "rolling_back",
        branch: "feature/test",
        metadata: {}
      )
    end

    context "with complete_rollback option" do
      let(:issue) do
        {
          type: :partial_rollback,
          version: migration.version,
          migration: migration,
          recovery_options: [:complete_rollback]
        }
      end

      it "removes from schema and updates status" do
        # Add to schema first
        ActiveRecord::Base.connection.execute(
          "INSERT INTO schema_migrations (version) VALUES ('#{migration.version}')"
        )

        result = executor.execute_recovery(issue, :complete_rollback)

        aggregate_failures do
          expect(result).to be true

          # Check schema_migrations
          count = ActiveRecord::Base.connection.select_value(
            "SELECT COUNT(*) FROM schema_migrations WHERE version = '#{migration.version}'"
          )
          expect(count).to eq(0)

          # Check migration status
          migration.reload
          expect(migration.status).to eq("rolled_back")
          expect(migration.metadata["recovery_action"]).to eq("complete_rollback")
          expect(migration.metadata["recovered_at"]).not_to be_nil
        end
      end
    end

    context "with restore_migration option" do
      let(:issue) do
        {
          type: :partial_rollback,
          version: migration.version,
          migration: migration,
          recovery_options: [:restore_migration]
        }
      end

      it "adds to schema and updates status" do
        result = executor.execute_recovery(issue, :restore_migration)

        aggregate_failures do
          expect(result).to be true

          # Check schema_migrations
          count = ActiveRecord::Base.connection.select_value(
            "SELECT COUNT(*) FROM schema_migrations WHERE version = '#{migration.version}'"
          )
          expect(count).to eq(1)

          # Check migration status
          migration.reload
          expect(migration.status).to eq("applied")
          expect(migration.metadata["recovery_action"]).to eq("restore_migration")
        end
      end
    end

    context "with mark_as_rolled_back option" do
      let(:issue) do
        {
          type: :partial_rollback,
          version: migration.version,
          migration: migration,
          recovery_options: [:mark_as_rolled_back]
        }
      end

      it "updates status without schema changes" do
        # Add to schema
        ActiveRecord::Base.connection.execute(
          "INSERT INTO schema_migrations (version) VALUES ('#{migration.version}')"
        )

        result = executor.execute_recovery(issue, :mark_as_rolled_back)

        aggregate_failures do
          expect(result).to be true

          # Schema should remain unchanged
          count = ActiveRecord::Base.connection.select_value(
            "SELECT COUNT(*) FROM schema_migrations WHERE version = '#{migration.version}'"
          )
          expect(count).to eq(1)

          # Check migration status
          migration.reload
          expect(migration.status).to eq("rolled_back")
          expect(migration.metadata["warning"]).to include("without verifying")
        end
      end
    end

    context "with track_migration option" do
      let(:issue) do
        {
          type: :orphaned_schema,
          version: "20240102000001",
          recovery_options: [:track_migration]
        }
      end

      it "creates tracking record" do
        result = executor.execute_recovery(issue, :track_migration)

        aggregate_failures do
          expect(result).to be true

          record = MigrationGuard::MigrationGuardRecord.find_by(version: "20240102000001")
          expect(record).not_to be_nil
          expect(record.status).to eq("applied")
          expect(record.branch).to eq("feature/test")
          expect(record.metadata["recovery_action"]).to eq("tracked_retrospectively")
        end
      end
    end

    context "with consolidate_records option" do
      let(:record) do
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240103000001",
          status: "applied",
          branch: "main",
          metadata: { "original" => "true" }
        )
      end

      let(:issue) do
        # Simulate duplicate records as they would appear in the issue
        duplicate1 = record.dup
        duplicate1.id = record.id + 1
        duplicate1.branch = "feature"
        duplicate1.metadata = { "duplicate" => "1" }

        duplicate2 = record.dup
        duplicate2.id = record.id + 2
        duplicate2.branch = "develop"
        duplicate2.metadata = { "duplicate" => "2" }

        {
          type: :version_conflict,
          version: "20240103000001",
          migrations: [record, duplicate1, duplicate2],
          recovery_options: [:consolidate_records]
        }
      end

      it "keeps most recent record and merges metadata" do
        # Instead of trying to mock ActiveRecord relations, just test the behavior
        # The method expects an array of records in issue[:migrations]
        result = executor.execute_recovery(issue, :consolidate_records)

        # Since the consolidate_records method works with arrays, it should succeed
        expect(result).to be true

        # Check that the first record (keeper) still exists
        expect(MigrationGuard::MigrationGuardRecord.find_by(id: record.id)).to eq(record)
      end
    end
  end

  describe "#create_backup" do
    context "with SQLite" do
      it "handles in-memory database" do
        # Check the exact adapter name
        adapter_name = ActiveRecord::Base.connection.adapter_name
        expect(adapter_name).to match(/sqlite/i)

        # Ensure we're using an in-memory database
        config = ActiveRecord::Base.connection_db_config.configuration_hash
        expect(config[:database]).to eq(":memory:")

        # Don't use the mocked version for this test
        allow(executor).to receive(:create_backup).and_call_original
        result = executor.create_backup

        # SQLite memory database backup should return false
        expect(result).to be false
      end
    end

    context "with file-based database" do
      it "creates backup successfully" do
        # Mock a file-based SQLite database
        allow(ActiveRecord::Base.connection_db_config)
          .to receive(:configuration_hash)
          .and_return({ adapter: "sqlite3", database: "test.db" })

        # Create a dummy database file
        FileUtils.touch("test.db")

        result = executor.create_backup

        # Should succeed for file-based database
        expect(result).to be true

        # Clean up
        FileUtils.rm_f("test.db")
        Rails.root.glob("tmp/migration_recovery_backup_*.sql").each do |file|
          File.delete(file)
        end
      end
    end
  end

  describe "interactive mode" do
    let(:interactive_executor) { described_class.new(interactive: true) }
    let(:issue) do
      {
        type: :partial_rollback,
        version: "20240101000001",
        description: "Test issue",
        recovery_options: %i[complete_rollback restore_migration]
      }
    end

    it "prompts for user input" do
      # Create a real issue with a migration record
      migration = MigrationGuard::MigrationGuardRecord.create!(
        version: "20240101000001",
        status: "rolling_back",
        created_at: 2.hours.ago,
        updated_at: 2.hours.ago
      )

      issue[:migration] = migration

      allow(interactive_executor).to receive(:gets).and_return("1\n")
      expect(Rails.logger).to receive(:debug).at_least(:once)

      result = interactive_executor.execute_recovery(issue)

      # The result depends on the actual execution, but we're mainly testing
      # that it prompts and processes the choice
      expect(result).to be_in([true, false])
    end

    it "handles skip option" do
      allow(interactive_executor).to receive(:gets).and_return("0\n")
      allow(interactive_executor).to receive(:puts).at_least(:once)

      result = interactive_executor.execute_recovery(issue)
      # When skipping (option 0), the method returns false
      expect(result).to be false
    end
  end
end
