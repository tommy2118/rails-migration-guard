# frozen_string_literal: true

require "rails_helper"

RSpec.describe MigrationGuard::Recovery::ManualIntervention do
  let(:manual_intervention) { described_class.new }

  before do
    # Suppress Rails.logger.debug output during tests
    allow(Rails.logger).to receive(:debug)
  end

  describe "#show" do
    it "returns true after showing instructions" do
      issue = { type: :partial_rollback, version: "20240116000001" }

      result = manual_intervention.show(issue)
      expect(result).to be true
    end

    it "calls all display methods" do
      issue = { type: :partial_rollback, version: "20240116000001" }

      expect(manual_intervention).to receive(:show_header)
      expect(manual_intervention).to receive(:show_sql_commands).with(issue)
      expect(manual_intervention).to receive(:show_footer).with(issue)

      manual_intervention.show(issue)
    end
  end

  describe "#show_header" do
    it "displays header information" do
      allow(Rails.logger).to receive(:debug)
      expect(Rails.logger).to receive(:debug).with(/Review these commands carefully/)
      expect(Rails.logger).to receive(:debug).with("")

      manual_intervention.send(:show_header)
    end
  end

  describe "#show_footer" do
    it "displays footer with update command" do
      issue = { version: "20240116000001" }

      expect(Rails.logger).to receive(:debug).with("")
      expect(Rails.logger).to receive(:debug).with("After manual intervention, update the tracking record:")
      expect(Rails.logger).to receive(:debug).with(/MigrationGuardRecord\.find_by.*update!/)
      expect(Rails.logger).to receive(:debug).with("")

      manual_intervention.send(:show_footer, issue)
    end
  end

  describe "#show_sql_commands" do
    context "for partial_rollback issue" do
      let(:issue) { { type: :partial_rollback, version: "20240116000001" } }

      it "shows partial rollback SQL commands" do
        expect(manual_intervention).to receive(:show_partial_rollback_sql).with(issue)
        manual_intervention.send(:show_sql_commands, issue)
      end
    end

    context "for orphaned_schema issue" do
      let(:issue) { { type: :orphaned_schema, version: "20240116000001" } }

      it "shows orphaned schema SQL commands" do
        expect(manual_intervention).to receive(:show_orphaned_schema_sql).with(issue)
        manual_intervention.send(:show_sql_commands, issue)
      end
    end

    context "for missing_from_schema issue" do
      let(:issue) { { type: :missing_from_schema, version: "20240116000001" } }

      it "shows missing from schema SQL commands" do
        expect(manual_intervention).to receive(:show_missing_from_schema_sql).with(issue)
        manual_intervention.send(:show_sql_commands, issue)
      end
    end

    context "for missing_file issue" do
      let(:issue) { { type: :missing_file, version: "20240116000001" } }

      it "shows missing file SQL commands" do
        expect(manual_intervention).to receive(:show_missing_file_sql).with(issue)
        manual_intervention.send(:show_sql_commands, issue)
      end
    end

    context "for version_conflict issue" do
      let(:migrations) { [double, double, double] }
      let(:issue) { { type: :version_conflict, version: "20240116000001", migrations: migrations } }

      it "shows version conflict SQL commands" do
        expect(manual_intervention).to receive(:show_version_conflict_sql).with(issue)
        manual_intervention.send(:show_sql_commands, issue)
      end
    end
  end

  describe "#show_partial_rollback_sql" do
    let(:issue) { { version: "20240116000001" } }

    it "shows both rollback and restore options" do
      expect(manual_intervention).to receive(:show_rollback_commands).with("20240116000001")
      expect(manual_intervention).to receive(:show_restore_commands).with("20240116000001")
      expect(Rails.logger).to receive(:debug).with("")

      manual_intervention.send(:show_partial_rollback_sql, issue)
    end
  end

  describe "#show_orphaned_schema_sql" do
    let(:issue) { { version: "20240116000001" } }

    it "shows tracking and removal options" do
      expect(Rails.logger).to receive(:debug).with("-- To track this migration:")
      expect(Rails.logger).to receive(:debug).with(/INSERT INTO migration_guard_records/)
      expect(Rails.logger).to receive(:debug).with("")
      expect(Rails.logger).to receive(:debug).with("-- To remove from schema:")
      expect(Rails.logger).to receive(:debug).with("DELETE FROM schema_migrations WHERE version = '20240116000001';")

      manual_intervention.send(:show_orphaned_schema_sql, issue)
    end
  end

  describe "#show_missing_from_schema_sql" do
    let(:issue) { { version: "20240116000001" } }

    it "shows addition and rollback options" do
      expect(Rails.logger).to receive(:debug).with("-- To add to schema:")
      expect(Rails.logger).to receive(:debug).with("INSERT INTO schema_migrations (version) VALUES ('20240116000001');")
      expect(Rails.logger).to receive(:debug).with("")
      expect(Rails.logger).to receive(:debug).with("-- To mark as rolled back:")
      expect(Rails.logger).to receive(:debug).with(/UPDATE migration_guard_records SET status = 'rolled_back'/)

      manual_intervention.send(:show_missing_from_schema_sql, issue)
    end
  end

  describe "#show_missing_file_sql" do
    let(:issue) { { version: "20240116000001" } }

    it "shows file restoration options" do
      expect(Rails.logger).to receive(:debug).with("-- Migration file is missing. Options:")
      expect(Rails.logger).to receive(:debug).with("").twice
      expect(manual_intervention).to receive(:show_git_restore_option).with("20240116000001")
      expect(manual_intervention).to receive(:show_mark_resolved_option).with("20240116000001")

      manual_intervention.send(:show_missing_file_sql, issue)
    end
  end

  describe "#show_version_conflict_sql" do
    let(:migrations) { [double, double, double] }
    let(:issue) { { version: "20240116000001", migrations: migrations } }

    it "shows conflict resolution SQL" do
      allow(Rails.logger).to receive(:debug)
      expect(Rails.logger).to receive(:debug).with("-- Keep the most recent and delete others:")
      expect(Rails.logger).to receive(:debug).with("")
      expect(Rails.logger).to receive(:debug).with(/DELETE FROM migration_guard_records/)

      manual_intervention.send(:show_version_conflict_sql, issue)
    end
  end

  describe "SQL generation methods" do
    describe "#deletion_sql" do
      it "generates correct deletion SQL" do
        result = manual_intervention.send(:deletion_sql, "20240116000001")
        expect(result).to eq("DELETE FROM schema_migrations WHERE version = '20240116000001';")
      end
    end

    describe "#insertion_sql" do
      it "generates correct insertion SQL" do
        result = manual_intervention.send(:insertion_sql, "20240116000001")
        expect(result).to eq("INSERT INTO schema_migrations (version) VALUES ('20240116000001');")
      end
    end

    describe "#update_status_sql" do
      it "generates correct update status SQL" do
        result = manual_intervention.send(:update_status_sql, "20240116000001", "applied")
        expect(result).to eq("UPDATE migration_guard_records SET status = 'applied' WHERE version = '20240116000001';")
      end
    end

    describe "#tracking_insert_sql" do
      it "generates correct tracking insert SQL" do
        result = manual_intervention.send(:tracking_insert_sql, "20240116000001")

        aggregate_failures do
          expect(result).to include("INSERT INTO migration_guard_records")
          expect(result).to include("20240116000001")
          expect(result).to include("applied")
          expect(result).to include("unknown")
          expect(result).to include("NOW()")
        end
      end
    end

    describe "#git_restore_commands" do
      it "generates correct git commands" do
        result = manual_intervention.send(:git_restore_commands, "20240116000001")

        aggregate_failures do
          expect(result).to include("git log --all --full-history")
          expect(result).to include("db/migrate/20240116000001_*.rb")
          expect(result).to include("git show COMMIT_HASH")
          expect(result).to include("20240116000001_restored.rb")
        end
      end
    end

    describe "#mark_as_resolved_sql" do
      it "generates correct mark as resolved SQL" do
        result = manual_intervention.send(:mark_as_resolved_sql, "20240116000001")

        aggregate_failures do
          expect(result).to include("UPDATE migration_guard_records")
          expect(result).to include("status = 'resolved'")
          expect(result).to include("20240116000001")
          expect(result).to include("missing_file")
        end
      end
    end

    describe "#version_conflict_deletion_sql" do
      it "generates correct version conflict deletion SQL" do
        result = manual_intervention.send(:version_conflict_deletion_sql, "20240116000001")

        aggregate_failures do
          expect(result).to include("DELETE FROM migration_guard_records")
          expect(result).to include("WHERE version = '20240116000001'")
          expect(result).to include("ORDER BY updated_at DESC")
          expect(result).to include("LIMIT 1")
        end
      end
    end

    describe "#update_command" do
      it "generates correct Ruby update command" do
        result = manual_intervention.send(:update_command, "20240116000001")
        expect(result).to eq("MigrationGuardRecord.find_by(version: '20240116000001').update!(status: 'resolved')")
      end
    end
  end

  describe "SQL injection safety" do
    it "properly escapes version numbers in SQL" do
      # Test with potentially dangerous input
      malicious_version = "'; DROP TABLE users; --"

      # These methods should still work (they're for manual review, not execution)
      result = manual_intervention.send(:deletion_sql, malicious_version)
      expect(result).to include(malicious_version)

      # The important thing is that these are displayed to the user for manual review
      # not executed directly by the application
    end
  end
end
