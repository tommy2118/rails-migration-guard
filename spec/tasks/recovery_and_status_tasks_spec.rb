# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "Recovery and status rake tasks", type: :integration do
  let(:rake_output) { StringIO.new }
  let(:original_logger) { Rails.logger }
  let(:test_logger) do
    logger = Logger.new(rake_output)
    logger.formatter = proc { |_severity, _time, _progname, msg| "#{msg}\n" }
    logger
  end
  let(:git_integration) { instance_double(MigrationGuard::GitIntegration) }

  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  before do
    Rake::Task.tasks.each(&:reenable) if Rake::Task.tasks.any?
    allow(Rails).to receive(:logger).and_return(test_logger)
    allow(MigrationGuard).to receive(:enabled?).and_return(true)

    # Setup git mocks
    allow(MigrationGuard::GitIntegration).to receive(:new).and_return(git_integration)
    allow(git_integration).to receive_messages(
      current_branch: "feature/test-branch",
      main_branch: "main",
      migration_versions_in_trunk: [],
      author_email: "test@example.com",
      current_author: "test@example.com"
    )

    MigrationGuard::MigrationGuardRecord.delete_all
    ActiveRecord::Base.connection.execute("DELETE FROM schema_migrations")
  end

  after do
    Rails.logger = original_logger
  end

  def task_output
    rake_output.string
  end

  def create_migration_record(version, **attributes)
    defaults = {
      status: "applied",
      branch: "feature/test-branch",
      author: "test@example.com",
      created_at: Time.current
    }
    MigrationGuard::MigrationGuardRecord.create!(
      version: version,
      **defaults.merge(attributes)
    )
  end

  describe "db:migration:status output formatting" do
    context "with clean state" do
      before do
        # All migrations in trunk
        %w[20240101000001 20240101000002].each do |version|
          create_migration_record(version, branch: "main")
        end
        allow(git_integration).to receive(:migration_versions_in_trunk)
          .and_return(%w[20240101000001 20240101000002])
      end

      it "shows all migrations synced" do
        Rake::Task["db:migration:status"].execute

        output = task_output
        expect(output).to include("Migration Status (main branch)")
        expect(output).to include("✓ All migrations synced with main: 2 migrations")
        expect(output).to include("✓ Synced: 2 migrations")
        expect(output).not_to include("Orphaned")
        expect(output).not_to include("Missing")
      end
    end

    context "with orphaned migrations on multiple branches" do
      before do
        # Main branch migrations
        create_migration_record("20240101000001", branch: "main")
        allow(git_integration).to receive(:migration_versions_in_trunk).and_return(["20240101000001"])

        # Orphaned migrations on different branches
        create_migration_record("20240102000001", branch: "feature/users", author: "alice@example.com",
                                                  created_at: 3.days.ago)
        create_migration_record("20240102000002", branch: "feature/users", author: "alice@example.com",
                                                  created_at: 2.days.ago)
        create_migration_record("20240103000001", branch: "feature/posts", author: "bob@example.com",
                                                  created_at: 1.day.ago)
        create_migration_record("20240104000001", branch: "feature/test-branch", author: "test@example.com")
      end

      # rubocop:disable RSpec/MultipleExpectations
      it "displays detailed orphaned migration report" do
        Rake::Task["db:migration:status"].execute

        output = task_output

        # Header information
        expect(output).to include("Migration Status (main branch)")
        expect(output).to include("✓ Synced: 1 migration")
        expect(output).to include("⚠ Orphaned: 4 migrations")

        # Orphaned migrations section
        expect(output).to include("Orphaned Migrations:")
        expect(output).to include("20240102000001")
        expect(output).to include("20240102000002")
        expect(output).to include("20240103000001")
        expect(output).to include("20240104000001")
        expect(output).to include("alice@example.com")
        expect(output).to include("bob@example.com")
        expect(output).to include("feature/users")
        expect(output).to include("feature/posts")
        expect(output).to include("feature/test-branch")
      end
      # rubocop:enable RSpec/MultipleExpectations
    end

    context "with missing migrations from trunk" do
      before do
        # Only one migration applied locally
        create_migration_record("20240101000001", branch: "main")

        # But trunk has two migrations
        allow(git_integration).to receive(:migration_versions_in_trunk)
          .and_return(%w[20240101000001 20240101000002])
      end

      it "shows missing migrations warning" do
        Rake::Task["db:migration:status"].execute

        output = task_output
        expect(output).to include("Migration Status (main branch)")
        expect(output).to include("✗ Missing: 1 migration (in trunk, not local)")
        expect(output).to include("Missing Migrations:")
        expect(output).to include("20240101000002")
        expect(output).to include("Run `rails db:migrate` to apply missing migrations")
      end
    end

    context "with mixed states" do
      before do
        # Various migration states
        create_migration_record("20240101000001", status: "applied", branch: "main")
        create_migration_record("20240101000002", status: "rolled_back", branch: "feature/old")
        create_migration_record("20240101000003", status: "applied", branch: "feature/current")

        allow(git_integration).to receive(:migration_versions_in_trunk).and_return(["20240101000001"])
      end

      it "only counts applied migrations as orphaned" do
        Rake::Task["db:migration:status"].execute

        output = task_output
        expect(output).to include("✓ Synced: 1 migration")
        expect(output).to include("⚠ Orphaned: 1 migration") # Only the applied one
        expect(output).not_to include("20240101000002") # Rolled back, not shown
        expect(output).to include("20240101000003") # Applied orphaned
      end
    end
  end

  describe "db:migration:recover task" do
    context "with no issues" do
      it "reports healthy state" do
        Rake::Task["db:migration:recover"].execute

        output = task_output
        expect(output).to include("No migration inconsistencies detected")
        # NOTE: The exact message format may vary - the key is that no issues are found
      end
    end

    context "with recovery issues" do
      before do
        # Create various inconsistent states

        # 1. Partial rollback (stuck in rolling_back state)
        stuck_migration = create_migration_record("20240101000001", status: "rolling_back")
        stuck_migration.update!(created_at: 2.hours.ago, updated_at: 2.hours.ago)

        # 2. Version conflict (duplicate records)
        # For this test, we'll simulate version conflicts differently since we have a unique constraint
        # We'll create two records with slightly different versions that should be the same
        create_migration_record("20240102000001", branch: "feature/a")
        # Instead of actual duplicates, we'll test with similar versions that indicate a conflict
        create_migration_record("20240102000001_v2", branch: "feature/b",
                                                     metadata: { original_version: "20240102000001" })

        # 3. Orphaned schema entry (in schema_migrations but not tracked)
        ActiveRecord::Base.connection.execute("INSERT INTO schema_migrations (version) VALUES ('20240103000001')")

        # 4. Missing from schema (tracked as applied but not in schema_migrations)
        create_migration_record("20240104000001", status: "applied")
      end

      # rubocop:disable RSpec/MultipleExpectations
      it "displays comprehensive analysis report" do
        # Mock stdin to skip through any prompts
        allow(MigrationGuard::RecoveryExecutor).to receive(:new).and_wrap_original do |method, *args, **kwargs|
          executor = method.call(*args, **kwargs)
          allow(executor).to receive(:gets).and_return("0\n")
          executor
        end

        Rake::Task["db:migration:recover"].execute

        output = task_output

        # The analyzer should detect issues (more than 4 because missing files are also detected)
        expect(output).to include("Detected migration inconsistencies")

        # Issue types should be present in the output
        expect(output).to include("Partial rollback")
        expect(output).to include("20240101000001")
        expect(output).to include("stuck in rollback state")

        expect(output).to include("Orphaned schema")
        expect(output).to include("20240103000001")

        expect(output).to include("Missing from schema")
        expect(output).to include("20240104000001")

        # Recovery process indicators
        expect(output).to include("Recovery options")
      end
      # rubocop:enable RSpec/MultipleExpectations

      context "with AUTO=true" do
        it "executes recovery automatically" do
          ENV["AUTO"] = "true"
          Rake::Task["db:migration:recover"].execute

          output = task_output
          expect(output).to include("Running in automatic mode")
          expect(output).to include("Processing:")
          expect(output).to include("Issue resolved")
        ensure
          ENV.delete("AUTO")
        end
      end

      context "when running interactive recovery" do
        it "prompts for recovery actions" do
          # Simulate selecting recovery option and then exiting
          allow(MigrationGuard::RecoveryExecutor).to receive(:new).and_wrap_original do |method, *args, **kwargs|
            executor = method.call(*args, **kwargs)
            allow(executor).to receive(:gets).and_return("1\n", "0\n")
            executor
          end

          Rake::Task["db:migration:recover"].execute

          output = task_output
          expect(output).to include("Running in interactive mode")
          expect(output).to include("Recovery options")
          expect(output).to include("Select option")
        end
      end
    end
  end

  describe "db:migration:doctor diagnostic output" do
    before do
      # Create some tracking records
      create_migration_record("20240101000001")
      create_migration_record("20240102000001")

      # Mock DiagnosticRunner to use Rails.logger instead of puts
      # rubocop:disable RSpec/AnyInstance
      allow_any_instance_of(MigrationGuard::DiagnosticRunner).to receive(:puts) do |_, message|
        Rails.logger.info message if message.present?
      end
      # rubocop:enable RSpec/AnyInstance
    end

    # rubocop:disable RSpec/MultipleExpectations
    it "displays comprehensive diagnostic information" do
      Rake::Task["db:migration:doctor"].execute

      output = task_output

      # Check for diagnostic sections
      expect(output).to include("Running Migration Guard Diagnostics...")

      # Basic checks should be present
      expect(output).to include("✓ Database connection")
      expect(output).to include("✓ Migration guard tables: 2 records")
      expect(output).to include("✓ Git repository: current: feature/test-branch")
      expect(output).to include("✓ Git branch detection: main: main")

      # Should detect orphaned migrations
      expect(output).to include("✗ Orphaned migrations: 2 found")

      # Should provide recommendations
      expect(output).to include("Issues Found:")
      expect(output).to include("Orphaned migrations detected:")
      expect(output).to include("rails db:migration:rollback_orphaned")

      # Overall status
      expect(output).to include("Overall Status: NEEDS ATTENTION")
    end
    # rubocop:enable RSpec/MultipleExpectations

    context "with git issues" do
      before do
        allow(git_integration).to receive(:current_branch)
          .and_raise(MigrationGuard::GitError, "Not a git repository")

        # rubocop:disable RSpec/AnyInstance
        allow_any_instance_of(MigrationGuard::DiagnosticRunner).to receive(:puts) do |_, message|
          Rails.logger.info message if message.present?
        end
        # rubocop:enable RSpec/AnyInstance
      end

      it "reports git integration issues" do
        Rake::Task["db:migration:doctor"].execute

        output = task_output
        expect(output).to include("✗ Git repository")
        expect(output).to include("Not a git repository")
        expect(output).to include("Git repository not found or not configured")
        expect(output).to include("Overall Status: NEEDS ATTENTION")
      end
    end
  end

  describe "output format options" do
    context "when JSON format is requested" do
      it "detects JSON format request" do
        ENV["FORMAT"] = "json"

        # For now, most tasks don't support JSON, so they should still work
        expect { Rake::Task["db:migration:status"].execute }.not_to raise_error

        # Future: Check for actual JSON output when implemented
      ensure
        ENV.delete("FORMAT")
      end
    end
  end

  describe "colorized output handling" do
    it "includes color codes in output" do
      create_migration_record("20240101000001")
      Rake::Task["db:migration:status"].execute

      output = task_output
      # Check for ANSI color codes or emoji indicators
      expect(output).to match(/\e\[|✓|⚠|✗|🔄|💡/) # Either ANSI codes or emoji
    end
  end
end
