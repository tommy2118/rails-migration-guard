# frozen_string_literal: true

require "rails_helper"

RSpec.describe MigrationGuard::Recovery::BaseAction do
  let(:base_action) { described_class.new }
  let(:git_integration) { instance_double(MigrationGuard::GitIntegration) }

  before do
    allow(MigrationGuard::GitIntegration).to receive(:new).and_return(git_integration)
  end

  describe "#initialize" do
    it "creates a GitIntegration instance" do
      expect(base_action.git_integration).to eq(git_integration)
    end
  end

  describe "#migration_exists_in_schema?" do
    let(:version) { "20240116000001" }

    context "when migration exists in schema" do
      it "returns true" do
        allow(ActiveRecord::Base.connection).to receive(:select_value)
          .with("SELECT 1 FROM schema_migrations WHERE version = '#{version}'")
          .and_return(1)

        expect(base_action.send(:migration_exists_in_schema?, version)).to be true
      end
    end

    context "when migration does not exist in schema" do
      it "returns false" do
        allow(ActiveRecord::Base.connection).to receive(:select_value)
          .with("SELECT 1 FROM schema_migrations WHERE version = '#{version}'")
          .and_return(nil)

        expect(base_action.send(:migration_exists_in_schema?, version)).to be false
      end
    end

    it "uses parameterized query to prevent SQL injection" do
      expect(ActiveRecord::Base).to receive(:sanitize_sql)
        .with(["SELECT 1 FROM schema_migrations WHERE version = ?", version])
        .and_return("SELECT 1 FROM schema_migrations WHERE version = '#{version}'")

      allow(ActiveRecord::Base.connection).to receive(:select_value).and_return(nil)

      base_action.send(:migration_exists_in_schema?, version)
    end
  end

  describe "#update_migration_metadata" do
    let(:migration) do
      MigrationGuard::MigrationGuardRecord.create!(
        version: "20240116000001",
        status: "applied",
        metadata: { "existing_key" => "existing_value" }
      )
    end
    let(:action_name) { "test_action" }

    before do
      allow(Time).to receive(:current).and_return(Time.zone.parse("2024-01-16 12:00:00"))
    end

    it "updates migration metadata with recovery action and timestamp" do
      expected_metadata = {
        "existing_key" => "existing_value",
        "recovery_action" => "test_action",
        "recovered_at" => "2024-01-16T12:00:00Z"
      }

      base_action.send(:update_migration_metadata, migration, action_name)

      migration.reload
      expect(migration.metadata).to eq(expected_metadata)
    end

    it "merges additional metadata when provided" do
      additional_metadata = { "extra_field" => "extra_value", "status" => "completed" }

      expected_metadata = {
        "existing_key" => "existing_value",
        "recovery_action" => "test_action",
        "recovered_at" => "2024-01-16T12:00:00Z",
        "extra_field" => "extra_value",
        "status" => "completed"
      }

      base_action.send(:update_migration_metadata, migration, action_name, additional_metadata)

      migration.reload
      expect(migration.metadata).to eq(expected_metadata)
    end

    it "overwrites existing recovery metadata" do
      migration_with_recovery = MigrationGuard::MigrationGuardRecord.create!(
        version: "20240116000002",
        status: "applied",
        metadata: {
          "recovery_action" => "old_action",
          "recovered_at" => "2023-01-01T00:00:00+00:00"
        }
      )

      expected_metadata = {
        "recovery_action" => "test_action",
        "recovered_at" => "2024-01-16T12:00:00Z"
      }

      base_action.send(:update_migration_metadata, migration_with_recovery, action_name)

      migration_with_recovery.reload
      expect(migration_with_recovery.metadata).to eq(expected_metadata)
    end
  end

  describe "logging methods" do
    let(:logger) { instance_double(Logger) }

    before do
      allow(Rails).to receive(:logger).and_return(logger)
    end

    describe "#log_success" do
      it "logs success message with colorization" do
        message = "Operation completed successfully"
        expect(MigrationGuard::Colorizer).to receive(:success).with(message).and_return("[SUCCESS] #{message}")
        expect(logger).to receive(:info).with("[SUCCESS] #{message}")

        base_action.send(:log_success, message)
      end
    end

    describe "#log_error" do
      it "logs error message with colorization" do
        message = "Operation failed"
        expect(MigrationGuard::Colorizer).to receive(:error).with(message).and_return("[ERROR] #{message}")
        expect(logger).to receive(:error).with("[ERROR] #{message}")

        base_action.send(:log_error, message)
      end
    end

    describe "#log_info" do
      it "logs info message with colorization" do
        message = "Processing migration"
        expect(MigrationGuard::Colorizer).to receive(:info).with(message).and_return("[INFO] #{message}")
        expect(logger).to receive(:info).with("[INFO] #{message}")

        base_action.send(:log_info, message)
      end
    end

    context "when Rails.logger is nil" do
      before do
        allow(Rails).to receive(:logger).and_return(nil)
      end

      it "does not raise errors when logging" do
        expect { base_action.send(:log_success, "test") }.not_to raise_error
        expect { base_action.send(:log_error, "test") }.not_to raise_error
        expect { base_action.send(:log_info, "test") }.not_to raise_error
      end
    end
  end

  describe "protected method visibility" do
    it "has protected helper methods" do
      expect(base_action.protected_methods).to include(
        :migration_exists_in_schema?,
        :update_migration_metadata,
        :log_success,
        :log_error,
        :log_info
      )
    end

    it "does not expose protected methods publicly" do
      expect(base_action.public_methods(false)).not_to include(
        :migration_exists_in_schema?,
        :update_migration_metadata,
        :log_success,
        :log_error,
        :log_info
      )
    end
  end
end
