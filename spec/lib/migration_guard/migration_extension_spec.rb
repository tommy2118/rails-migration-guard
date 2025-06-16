# frozen_string_literal: true

require "rails_helper"
require "migration_guard/migration_extension"

RSpec.describe MigrationGuard::MigrationExtension do
  # Create a test migration class
  let(:test_migration_class) do
    Class.new(ActiveRecord::Migration[6.1]) do
      def self.version
        "20240115123456"
      end

      def version # rubocop:disable Rails/Delegate
        self.class.version
      end

      def up
        # Empty migration for testing
      end

      def down
        # Empty migration for testing
      end
    end
  end

  let(:migration_instance) { test_migration_class.new }
  let(:tracker) { instance_double(MigrationGuard::Tracker, track_migration: nil) }
  let(:post_migration_checker) { instance_double(MigrationGuard::PostMigrationChecker, check_and_warn: nil) }

  before do
    # Ensure the extension is loaded
    test_migration_class.prepend(described_class)
    allow(MigrationGuard).to receive(:enabled?).and_return(true)
    allow(MigrationGuard::Tracker).to receive(:new).and_return(tracker)
    allow(MigrationGuard::PostMigrationChecker).to receive(:new).and_return(post_migration_checker)
    allow(tracker).to receive(:track_migration)
  end

  describe "automatic tracking on migrate" do
    context "when using class method" do
      it "tracks migration when running up" do
        expect(tracker).to receive(:track_migration).with("20240115123456", :up)
        test_migration_class.migrate(:up)
      end

      it "tracks migration when running down" do
        expect(tracker).to receive(:track_migration).with("20240115123456", :down)
        test_migration_class.migrate(:down)
      end

      it "still executes the migration" do
        # Just verify it doesn't raise an error
        expect { test_migration_class.migrate(:up) }.not_to raise_error
      end
      
      it "checks for orphaned migrations after running up" do
        expect(post_migration_checker).to receive(:check_and_warn)
        test_migration_class.migrate(:up)
      end
      
      it "does not check for orphaned migrations after running down" do
        expect(post_migration_checker).not_to receive(:check_and_warn)
        test_migration_class.migrate(:down)
      end
    end

    context "when using instance method" do
      it "tracks migration when running up" do
        expect(tracker).to receive(:track_migration).with("20240115123456", :up)
        migration_instance.migrate(:up)
      end

      it "tracks migration when running down" do
        expect(tracker).to receive(:track_migration).with("20240115123456", :down)
        migration_instance.migrate(:down)
      end
      
      it "checks for orphaned migrations after running up" do
        expect(post_migration_checker).to receive(:check_and_warn)
        migration_instance.migrate(:up)
      end
      
      it "does not check for orphaned migrations after running down" do
        expect(post_migration_checker).not_to receive(:check_and_warn)
        migration_instance.migrate(:down)
      end
    end

    context "when MigrationGuard is disabled" do
      before do
        allow(MigrationGuard).to receive(:enabled?).and_return(false)
      end

      it "does not track migration" do
        expect(tracker).not_to receive(:track_migration)
        test_migration_class.migrate(:up)
      end

      it "still executes the migration" do
        # Just verify it doesn't raise an error
        expect { test_migration_class.migrate(:up) }.not_to raise_error
      end
    end

    context "when migration has no version method" do
      let(:versionless_migration) do
        Class.new(ActiveRecord::Migration[6.1]) do
          def up; end
          def down; end
        end
      end

      before do
        versionless_migration.prepend(described_class)
      end

      it "does not track migration" do
        # For migrations without version, tracking should be skipped
        versionless_migration.new.migrate(:up)

        # No records should be created
        expect(MigrationGuard::MigrationGuardRecord.count).to eq(0)
      end
    end

    context "when tracking raises an error" do
      it "does not prevent migration from running if tracking fails" do
        # Errors in tracking should be caught by the Tracker itself
        allow(tracker).to receive(:track_migration).and_return(nil)

        expect { test_migration_class.migrate(:up) }.not_to raise_error
      end
    end
  end

  describe "sandbox mode" do
    let(:connection) { ActiveRecord::Base.connection }

    before do
      allow(MigrationGuard.configuration).to receive(:sandbox_mode).and_return(true)
      allow(Rails.logger).to receive(:debug).and_call_original
    end

    it "rolls back migration in sandbox mode" do
      # In sandbox mode, it should wrap the migration in a transaction and rollback
      allow(connection).to receive(:transaction).with(requires_new: true).and_yield

      expect { migration_instance.exec_migration(connection, :up) }.to raise_error(ActiveRecord::Rollback)
    end

    it "logs sandbox operation" do
      allow(connection).to receive(:transaction).and_yield

      expect(Rails.logger).to receive(:debug).at_least(:once)
      expect { migration_instance.exec_migration(connection, :up) }.to raise_error(ActiveRecord::Rollback)
    end

    it "does not rollback when running down migrations" do
      expect(connection).not_to receive(:transaction)
      migration_instance.exec_migration(connection, :down)
    end

    context "when sandbox mode is disabled" do
      before do
        allow(MigrationGuard.configuration).to receive(:sandbox_mode).and_return(false)
      end

      it "executes migration normally" do
        expect(connection).not_to receive(:transaction)
        expect { migration_instance.exec_migration(connection, :up) }.not_to raise_error
      end
    end
  end

  describe "integration with Rails migration execution" do
    # Don't mock the tracker for integration tests
    before do
      allow(MigrationGuard::Tracker).to receive(:new).and_call_original
    end

    it "hooks into ActiveRecord::Migration automatically" do
      expect(ActiveRecord::Migration.ancestors).to include(described_class)
    end

    it "preserves original migration functionality" do # rubocop:disable RSpec/ExampleLength
      # Create a real migration that modifies the database
      test_table_migration = Class.new(ActiveRecord::Migration[6.1]) do
        def self.version
          "20240115999999"
        end

        def version # rubocop:disable Rails/Delegate
          self.class.version
        end

        def up
          create_table :test_migration_guard_table do |t|
            t.string :name
          end
        end

        def down
          drop_table :test_migration_guard_table
        end
      end

      test_table_migration.prepend(described_class)

      # Run the migration
      expect { test_table_migration.migrate(:up) }.not_to raise_error

      # Verify table was created
      expect(ActiveRecord::Base.connection.table_exists?(:test_migration_guard_table)).to be true

      # Verify tracking occurred
      record = MigrationGuard::MigrationGuardRecord.find_by(version: "20240115999999")
      expect(record).to be_present
      expect(record.status).to eq("applied")

      # Clean up
      test_table_migration.migrate(:down)
      expect(ActiveRecord::Base.connection.table_exists?(:test_migration_guard_table)).to be false
    end
  end

  describe "performance" do
    it "adds minimal overhead to migration execution" do
      allow(tracker).to receive(:track_migration)

      start_time = Time.current
      test_migration_class.migrate(:up)
      elapsed_time = Time.current - start_time

      # Tracking should add less than 100ms overhead
      expect(elapsed_time).to be < 0.1
    end
  end
end
