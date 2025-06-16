# frozen_string_literal: true

require "rails_helper"

RSpec.describe MigrationGuard::Recovery::SchemaAction do
  let(:schema_action) { described_class.new }
  let(:migration) do
    MigrationGuard::MigrationGuardRecord.create!(
      version: "20240116000001",
      status: "applied",
      metadata: {}
    )
  end

  before do
    # Clear schema_migrations
    ActiveRecord::Base.connection.execute("DELETE FROM schema_migrations")
    # Mock time for consistent tests
    allow(Time).to receive(:current).and_return(Time.zone.parse("2024-01-16 12:00:00"))
  end

  describe "#remove_from_schema" do
    let(:issue) { { version: "20240116000001" } }

    context "when version exists in schema" do
      before do
        ActiveRecord::Base.connection.execute(
          ActiveRecord::Base.sanitize_sql(
            ["INSERT INTO schema_migrations (version) VALUES (?)", issue[:version]]
          )
        )
      end

      it "removes version from schema_migrations" do
        expect(schema_action).to receive(:log_info).with("Removing #{issue[:version]} from schema_migrations...")
        expect(schema_action).to receive(:log_success).with("✓ Removed from schema: #{issue[:version]}")

        result = schema_action.remove_from_schema(issue)

        aggregate_failures do
          expect(result).to be true

          # Verify removal
          count = ActiveRecord::Base.connection.select_value(
            ActiveRecord::Base.sanitize_sql(
              ["SELECT COUNT(*) FROM schema_migrations WHERE version = ?", issue[:version]]
            )
          )
          expect(count).to eq(0)
        end
      end

      it "uses parameterized query for safety" do
        malicious_version = "'; DROP TABLE users; --"
        issue_with_injection = { version: malicious_version }

        expect(ActiveRecord::Base).to receive(:sanitize_sql)
          .with(["DELETE FROM schema_migrations WHERE version = ?", malicious_version])
          .and_call_original

        schema_action.remove_from_schema(issue_with_injection)
      end
    end

    context "when an error occurs" do
      it "returns false and logs error" do
        allow(schema_action).to receive(:execute_schema_deletion).and_raise(StandardError, "Database error")
        expect(schema_action).to receive(:log_info).with("Removing #{issue[:version]} from schema_migrations...")
        expect(schema_action).to receive(:log_error).with("✗ Failed to remove from schema: Database error")

        result = schema_action.remove_from_schema(issue)
        expect(result).to be false
      end
    end
  end

  describe "#reapply_migration" do
    let(:issue) { { migration: migration } }
    let(:migration_file) { Rails.root.join("db/migrate/20240116000001_create_test_table.rb") }

    context "when migration file exists" do
      before do
        allow(Rails.root).to receive(:glob).with("db/migrate/#{migration.version}_*.rb").and_return([migration_file])
      end

      it "runs the migration" do # rubocop:disable RSpec/MultipleExpectations
        # Create a mock migration class
        migration_class = Class.new(ActiveRecord::Migration[6.1]) do
          def up
            # Mock migration
          end
        end
        stub_const("CreateTestTable", migration_class)

        expect(schema_action).to receive(:log_info).with("Re-applying migration #{migration.version}...")
        expect(schema_action).to receive(:log_success).with("✓ Migration re-applied: #{migration.version}")
        expect(schema_action).to receive(:require).with(migration_file)

        # Mock the migration execution
        migration_instance = instance_double(migration_class)
        expect(migration_class).to receive(:new).and_return(migration_instance)
        expect(migration_instance).to receive(:version=).with(migration.version)
        expect(migration_instance).to receive(:migrate).with(:up)

        result = schema_action.reapply_migration(issue)
        expect(result).to be true
      end

      it "updates migration status after successful re-apply" do
        # Create a mock migration class
        migration_class = Class.new(ActiveRecord::Migration[6.1])
        stub_const("CreateTestTable", migration_class)

        allow(schema_action).to receive(:require).with(migration_file)
        allow(schema_action).to receive(:run_migration)
        allow(schema_action).to receive(:log_info)
        allow(schema_action).to receive(:log_success)

        schema_action.reapply_migration(issue)

        migration.reload
        aggregate_failures do
          expect(migration.status).to eq("applied")
          expect(migration.metadata["recovery_action"]).to eq("reapplied")
          expect(migration.metadata["recovered_at"]).to eq("2024-01-16T12:00:00Z")
        end
      end

      it "handles migration execution errors" do
        migration_class = Class.new(ActiveRecord::Migration[6.1]) do
          def up
            raise "Migration failed"
          end
        end
        stub_const("CreateTestTable", migration_class)

        allow(schema_action).to receive(:require).with(migration_file)
        allow(schema_action).to receive(:run_migration).and_raise(StandardError, "Migration failed")

        expect(schema_action).to receive(:log_error).with("✗ Failed to re-apply migration: Migration failed")

        result = schema_action.reapply_migration(issue)
        expect(result).to be false
      end
    end

    context "when migration file doesn't exist" do
      before do
        allow(Rails.root).to receive(:glob).with("db/migrate/#{migration.version}_*.rb").and_return([])
      end

      it "returns false and logs error" do
        expect(schema_action).to receive(:log_info).with("Re-applying migration #{migration.version}...")
        expect(schema_action).to receive(:log_error).with("Migration file not found for #{migration.version}")

        result = schema_action.reapply_migration(issue)
        expect(result).to be false
      end
    end
  end

  describe "private methods" do
    describe "#extract_migration_class_name" do
      it "extracts class name from migration file path" do
        test_cases = {
          "20240116000001_create_users.rb" => "CreateUsers",
          "20240116000002_add_email_to_users.rb" => "AddEmailToUsers",
          "20240116000003_add_index_on_users_email.rb" => "AddIndexOnUsersEmail"
        }

        test_cases.each do |filename, expected_class|
          result = schema_action.send(:extract_migration_class_name, filename)
          expect(result).to eq(expected_class)
        end
      end
    end

    describe "#find_migration_file" do
      it "finds migration file by version" do
        version = "20240116000001"
        expected_path = Rails.root.join("db/migrate/#{version}_create_test.rb")

        allow(Rails.root).to receive(:glob)
          .with("db/migrate/#{version}_*.rb")
          .and_return([expected_path])

        result = schema_action.send(:find_migration_file, version)
        expect(result).to eq(expected_path)
      end

      it "returns nil when file not found" do
        version = "20240116000002"

        allow(Rails.root).to receive(:glob)
          .with("db/migrate/#{version}_*.rb")
          .and_return([])

        result = schema_action.send(:find_migration_file, version)
        expect(result).to be_nil
      end
    end

    describe "#load_migration_class" do
      it "constantizes the migration class name" do
        migration_file = "20240116000001_create_test_table.rb"
        test_migration_class = Class.new(ActiveRecord::Migration[6.1])

        expect(schema_action).to receive(:extract_migration_class_name)
          .with(migration_file)
          .and_return("CreateTestTable")

        allow(Object).to receive(:const_get).with("CreateTestTable").and_return(test_migration_class)

        result = schema_action.send(:load_migration_class, migration_file)
        expect(result).to eq(test_migration_class)
      end
    end

    describe "#update_reapply_status" do
      it "updates migration metadata and status" do
        schema_action.send(:update_reapply_status, migration)

        migration.reload
        aggregate_failures do
          expect(migration.status).to eq("applied")
          expect(migration.metadata["recovery_action"]).to eq("reapplied")
          expect(migration.metadata["recovered_at"]).to eq("2024-01-16T12:00:00Z")
        end
      end
    end
  end
end
