# frozen_string_literal: true

require "rails_helper"

RSpec.describe MigrationGuard::Recovery::RollbackAction do
  let(:rollback_action) { described_class.new }
  let(:migration) do
    MigrationGuard::MigrationGuardRecord.create!(
      version: "20240116000001",
      status: "rolling_back",
      metadata: {}
    )
  end

  before do
    # Clear schema_migrations
    ActiveRecord::Base.connection.execute("DELETE FROM schema_migrations")
    # Mock time for consistent tests
    allow(Time).to receive(:current).and_return(Time.zone.parse("2024-01-16 12:00:00"))
  end

  describe "#complete_rollback" do
    let(:issue) { { migration: migration, version: migration.version } }

    context "when migration exists in schema" do
      before do
        ActiveRecord::Base.connection.execute(
          ActiveRecord::Base.sanitize_sql(
            ["INSERT INTO schema_migrations (version) VALUES (?)", migration.version]
          )
        )
      end

      it "removes migration from schema_migrations" do
        expect(rollback_action).to receive(:log_info).with("Completing rollback for #{migration.version}...")
        expect(rollback_action).to receive(:log_success).with("✓ Rollback completed for #{migration.version}")

        result = rollback_action.complete_rollback(issue)

        aggregate_failures do
          expect(result).to be true

          # Verify removal from schema
          count = ActiveRecord::Base.connection.select_value(
            ActiveRecord::Base.sanitize_sql(
              ["SELECT COUNT(*) FROM schema_migrations WHERE version = ?", migration.version]
            )
          )
          expect(count).to eq(0)
        end
      end

      it "updates migration status to rolled_back" do
        rollback_action.complete_rollback(issue)

        migration.reload
        expect(migration.status).to eq("rolled_back")
      end

      it "updates migration metadata with recovery action" do
        rollback_action.complete_rollback(issue)

        migration.reload
        expected_metadata = {
          "recovery_action" => "complete_rollback",
          "recovered_at" => "2024-01-16T12:00:00Z"
        }
        expect(migration.metadata).to eq(expected_metadata)
      end
    end

    context "when migration doesn't exist in schema" do
      it "still completes successfully" do
        expect(rollback_action).to receive(:log_info).with("Completing rollback for #{migration.version}...")
        expect(rollback_action).to receive(:log_success).with("✓ Rollback completed for #{migration.version}")

        result = rollback_action.complete_rollback(issue)

        aggregate_failures do
          expect(result).to be true

          migration.reload
          expect(migration.status).to eq("rolled_back")
          expect(migration.metadata["recovery_action"]).to eq("complete_rollback")
        end
      end
    end

    context "when an error occurs" do
      it "returns false and logs error" do
        allow(rollback_action).to receive(:update_rollback_status).and_raise(StandardError, "Database error")
        expect(rollback_action).to receive(:log_error).with("✗ Failed to complete rollback: Database error")

        result = rollback_action.complete_rollback(issue)
        expect(result).to be false
      end

      it "doesn't update migration status on error" do
        allow(rollback_action).to receive(:update_rollback_status).and_raise(StandardError, "Database error")

        rollback_action.complete_rollback(issue)

        migration.reload
        expect(migration.status).to eq("rolling_back")
      end
    end
  end

  describe "#mark_as_rolled_back" do
    let(:issue) { { migration: migration, version: migration.version } }

    it "marks migration as rolled back without schema changes" do
      # Add to schema first
      ActiveRecord::Base.connection.execute(
        ActiveRecord::Base.sanitize_sql(
          ["INSERT INTO schema_migrations (version) VALUES (?)", migration.version]
        )
      )

      expect(rollback_action).to receive(:log_info).with("Marking #{migration.version} as rolled back...")
      expect(rollback_action).to receive(:log_success).with("✓ Marked as rolled back: #{migration.version}")

      result = rollback_action.mark_as_rolled_back(issue)

      aggregate_failures do
        expect(result).to be true

        # Schema should remain unchanged
        count = ActiveRecord::Base.connection.select_value(
          ActiveRecord::Base.sanitize_sql(
            ["SELECT COUNT(*) FROM schema_migrations WHERE version = ?", migration.version]
          )
        )
        expect(count).to eq(1)

        migration.reload
        expect(migration.status).to eq("rolled_back")
      end
    end

    it "adds warning to metadata" do
      rollback_action.mark_as_rolled_back(issue)

      migration.reload
      expected_metadata = {
        "recovery_action" => "marked_as_rolled_back",
        "recovered_at" => "2024-01-16T12:00:00Z",
        "warning" => "Status updated without verifying actual rollback"
      }
      expect(migration.metadata).to eq(expected_metadata)
    end

    it "preserves existing metadata" do
      migration.update!(metadata: { "original_branch" => "feature/test" })

      rollback_action.mark_as_rolled_back(issue)

      migration.reload
      expect(migration.metadata).to include(
        "original_branch" => "feature/test",
        "recovery_action" => "marked_as_rolled_back",
        "warning" => "Status updated without verifying actual rollback"
      )
    end
  end

  describe "private methods" do
    describe "#remove_from_schema_if_exists" do
      it "removes version from schema_migrations when it exists" do
        version = "20240116000002"
        ActiveRecord::Base.connection.execute(
          ActiveRecord::Base.sanitize_sql(
            ["INSERT INTO schema_migrations (version) VALUES (?)", version]
          )
        )

        rollback_action.send(:remove_from_schema_if_exists, version)

        count = ActiveRecord::Base.connection.select_value(
          ActiveRecord::Base.sanitize_sql(
            ["SELECT COUNT(*) FROM schema_migrations WHERE version = ?", version]
          )
        )
        expect(count).to eq(0)
      end

      it "does nothing when version doesn't exist" do
        version = "20240116000003"

        expect { rollback_action.send(:remove_from_schema_if_exists, version) }
          .not_to raise_error
      end

      it "uses parameterized query for safety" do
        version = "'; DROP TABLE schema_migrations; --"

        # First call for checking existence
        expect(ActiveRecord::Base).to receive(:sanitize_sql)
          .with(["SELECT 1 FROM schema_migrations WHERE version = ?", version])
          .and_call_original

        # Allow the method to not find the version
        allow(ActiveRecord::Base.connection).to receive(:select_value).and_return(nil)

        rollback_action.send(:remove_from_schema_if_exists, version)
      end
    end

    describe "#update_rollback_status" do
      it "updates migration metadata and status" do
        rollback_action.send(:update_rollback_status, migration)

        migration.reload
        aggregate_failures do
          expect(migration.status).to eq("rolled_back")
          expect(migration.metadata["recovery_action"]).to eq("complete_rollback")
          expect(migration.metadata["recovered_at"]).to eq("2024-01-16T12:00:00Z")
        end
      end
    end
  end
end
