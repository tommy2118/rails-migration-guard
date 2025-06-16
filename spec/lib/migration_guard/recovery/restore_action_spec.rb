# frozen_string_literal: true

require "rails_helper"

RSpec.describe MigrationGuard::Recovery::RestoreAction do
  let(:restore_action) { described_class.new }
  let(:migration) do
    MigrationGuard::MigrationGuardRecord.create!(
      version: "20240116000001",
      status: "rolling_back",
      branch: "feature/test",
      metadata: {}
    )
  end

  before do
    # Clear existing data
    MigrationGuard::MigrationGuardRecord.delete_all
    ActiveRecord::Base.connection.execute("DELETE FROM schema_migrations")
    # Mock time for consistent tests
    allow(Time).to receive(:current).and_return(Time.zone.parse("2024-01-16 12:00:00"))
  end

  describe "#restore_migration" do
    let(:issue) { { migration: migration } }

    it "restores migration and updates status" do
      expect(restore_action).to receive(:log_info).with("Restoring migration #{migration.version}...")
      expect(restore_action).to receive(:log_success).with("✓ Migration restored: #{migration.version}")

      result = restore_action.restore_migration(issue)

      aggregate_failures do
        expect(result).to be true

        migration.reload
        expect(migration.status).to eq("applied")
        expect(migration.metadata["recovery_action"]).to eq("restore_migration")
        expect(migration.metadata["recovered_at"]).to eq("2024-01-16T12:00:00Z")

        # Check that it was added to schema
        count = ActiveRecord::Base.connection.select_value(
          ActiveRecord::Base.sanitize_sql(
            ["SELECT COUNT(*) FROM schema_migrations WHERE version = ?", migration.version]
          )
        )
        expect(count).to eq(1)
      end
    end

    it "handles errors during restoration" do
      allow(restore_action).to receive(:add_to_schema_if_missing).and_raise(StandardError, "Database error")
      expect(restore_action).to receive(:log_info).with("Restoring migration #{migration.version}...")
      expect(restore_action).to receive(:log_error).with("✗ Failed to restore migration: Database error")

      result = restore_action.restore_migration(issue)
      expect(result).to be false
    end
  end

  describe "#restore_from_git" do
    let(:issue) { { version: "20240116000001" } }

    context "when migration is found in git history" do
      before do
        # Mock successful git operations
        allow(Open3).to receive(:capture3)
          .with("git", "log", "--all", "--full-history", "--", "db/migrate/20240116000001_*.rb")
          .and_return(["commit abc123def456\nAuthor: Test", "", double(success?: true)])

        allow(Open3).to receive(:capture3)
          .with("git", "show", "--name-only", "--pretty=format:", "abc123def456")
          .and_return(["db/migrate/20240116000001_create_test.rb\n", "", double(success?: true)])

        allow(Open3).to receive(:capture3)
          .with("git", "show", "abc123def456:db/migrate/20240116000001_create_test.rb")
          .and_return(["class CreateTest < ActiveRecord::Migration[6.1]\nend", "", double(success?: true)])

        allow(FileUtils).to receive(:mkdir_p)
        allow(File).to receive(:write)
      end

      it "successfully restores migration file from git" do
        expect(restore_action).to receive(:log_info).with("Attempting to restore migration 20240116000001 from git history...")
        expect(restore_action).to receive(:log_success).with("✓ Migration file restored from commit abc123def456")

        result = restore_action.restore_from_git(issue)

        aggregate_failures do
          expect(result).to be true
          expect(FileUtils).to have_received(:mkdir_p)
          expect(File).to have_received(:write)
        end
      end
    end

    context "when migration is not found in git history" do
      before do
        allow(Open3).to receive(:capture3)
          .with("git", "log", "--all", "--full-history", "--", "db/migrate/20240116000001_*.rb")
          .and_return(["", "", double(success?: false)])
      end

      it "returns false and logs error" do
        expect(restore_action).to receive(:log_info).with("Attempting to restore migration 20240116000001 from git history...")
        expect(restore_action).to receive(:log_error).with("Migration not found in git history")

        result = restore_action.restore_from_git(issue)
        expect(result).to be false
      end
    end

    context "when migration file is not found in commit" do
      before do
        allow(Open3).to receive(:capture3)
          .with("git", "log", "--all", "--full-history", "--", "db/migrate/20240116000001_*.rb")
          .and_return(["commit abc123def456\n", "", double(success?: true)])

        allow(Open3).to receive(:capture3)
          .with("git", "show", "--name-only", "--pretty=format:", "abc123def456")
          .and_return(["other_file.rb\n", "", double(success?: true)])
      end

      it "returns false and logs error" do
        expect(restore_action).to receive(:log_info).with("Attempting to restore migration 20240116000001 from git history...")
        expect(restore_action).to receive(:log_error).with("Could not find migration file in commit")

        result = restore_action.restore_from_git(issue)
        expect(result).to be false
      end
    end

    context "when git command fails" do
      before do
        allow(Open3).to receive(:capture3)
          .with("git", "log", "--all", "--full-history", "--", "db/migrate/20240116000001_*.rb")
          .and_return(["commit abc123def456\n", "", double(success?: true)])

        allow(Open3).to receive(:capture3)
          .with("git", "show", "--name-only", "--pretty=format:", "abc123def456")
          .and_return(["db/migrate/20240116000001_create_test.rb\n", "", double(success?: true)])

        allow(Open3).to receive(:capture3)
          .with("git", "show", "abc123def456:db/migrate/20240116000001_create_test.rb")
          .and_return(["", "fatal: bad object", double(success?: false)])
      end

      it "handles git show failures" do
        expect(restore_action).to receive(:log_info).with("Attempting to restore migration 20240116000001 from git history...")
        expect(restore_action).to receive(:log_error).with("Failed to restore file: fatal: bad object")

        result = restore_action.restore_from_git(issue)
        expect(result).to be false
      end
    end

    context "when an unexpected error occurs" do
      before do
        allow(Open3).to receive(:capture3).and_raise(StandardError, "Unexpected error")
      end

      it "handles unexpected errors" do
        expect(restore_action).to receive(:log_info).with("Attempting to restore migration 20240116000001 from git history...")
        expect(restore_action).to receive(:log_error).with("✗ Failed to restore from git: Unexpected error")

        result = restore_action.restore_from_git(issue)
        expect(result).to be false
      end
    end
  end

  describe "private methods" do
    describe "#find_migration_commit" do
      it "returns commit hash when migration is found" do
        allow(Open3).to receive(:capture3)
          .with("git", "log", "--all", "--full-history", "--", "db/migrate/20240116000001_*.rb")
          .and_return(["commit abc123def456\nAuthor: Test", "", double(success?: true)])

        result = restore_action.send(:find_migration_commit, "20240116000001")
        expect(result).to eq("abc123def456")
      end

      it "returns nil when migration is not found" do
        allow(Open3).to receive(:capture3)
          .with("git", "log", "--all", "--full-history", "--", "db/migrate/20240116000001_*.rb")
          .and_return(["", "", double(success?: false)])

        result = restore_action.send(:find_migration_commit, "20240116000001")
        expect(result).to be_nil
      end

      it "returns nil when output is empty" do
        allow(Open3).to receive(:capture3)
          .with("git", "log", "--all", "--full-history", "--", "db/migrate/20240116000001_*.rb")
          .and_return(["", "", double(success?: true)])

        result = restore_action.send(:find_migration_commit, "20240116000001")
        expect(result).to be_nil
      end
    end

    describe "#get_migration_file_path" do
      it "returns file path when found" do
        allow(Open3).to receive(:capture3)
          .with("git", "show", "--name-only", "--pretty=format:", "abc123")
          .and_return(["other_file.rb\ndb/migrate/20240116000001_create_test.rb\nanother_file.rb", "",
                       double(success?: true)])

        result = restore_action.send(:get_migration_file_path, "abc123", "20240116000001")
        expect(result).to eq("db/migrate/20240116000001_create_test.rb")
      end

      it "returns nil when file is not found" do
        allow(Open3).to receive(:capture3)
          .with("git", "show", "--name-only", "--pretty=format:", "abc123")
          .and_return(["other_file.rb\nanother_file.rb", "", double(success?: true)])

        result = restore_action.send(:get_migration_file_path, "abc123", "20240116000001")
        expect(result).to be_nil
      end

      it "returns nil when git command fails" do
        allow(Open3).to receive(:capture3)
          .with("git", "show", "--name-only", "--pretty=format:", "abc123")
          .and_return(["", "error", double(success?: false)])

        result = restore_action.send(:get_migration_file_path, "abc123", "20240116000001")
        expect(result).to be_nil
      end
    end

    describe "#restore_file_from_commit" do
      before do
        allow(FileUtils).to receive(:mkdir_p)
        allow(File).to receive(:write)
        allow(Rails.root).to receive(:join).with("db/migrate/test.rb").and_return("/app/db/migrate/test.rb")
      end

      it "creates directory and writes file on success" do
        allow(Open3).to receive(:capture3)
          .with("git", "show", "abc123:db/migrate/test.rb")
          .and_return(["file content", "", double(success?: true)])

        result = restore_action.send(:restore_file_from_commit, "abc123", "db/migrate/test.rb")

        aggregate_failures do
          expect(result).to be true
          expect(FileUtils).to have_received(:mkdir_p).with("/app/db/migrate")
          expect(File).to have_received(:write).with("/app/db/migrate/test.rb", "file content")
        end
      end

      it "handles git show failure" do
        allow(Open3).to receive(:capture3)
          .with("git", "show", "abc123:db/migrate/test.rb")
          .and_return(["", "fatal: bad object", double(success?: false)])

        expect(restore_action).to receive(:log_error).with("Failed to restore file: fatal: bad object")

        result = restore_action.send(:restore_file_from_commit, "abc123", "db/migrate/test.rb")
        expect(result).to be false
      end
    end

    describe "#update_restore_status" do
      it "updates migration metadata and status" do
        restore_action.send(:update_restore_status, migration)

        migration.reload
        aggregate_failures do
          expect(migration.status).to eq("applied")
          expect(migration.metadata["recovery_action"]).to eq("restore_migration")
          expect(migration.metadata["recovered_at"]).to eq("2024-01-16T12:00:00Z")
        end
      end
    end
  end
end
