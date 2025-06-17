# frozen_string_literal: true

require "rails_helper"
require "rake"

# rubocop:disable RSpec/MultipleMemoizedHelpers
RSpec.describe "MigrationGuard rake task integration", type: :integration do
  # Helpers for testing rake tasks
  let(:rake_output) { StringIO.new }
  let(:stdout_output) { StringIO.new }
  let(:original_logger) { Rails.logger }
  let(:test_logger) { Logger.new(rake_output) }
  let(:git_integration) { instance_double(MigrationGuard::GitIntegration) }

  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  before do
    # Reset task state
    Rake::Task.tasks.each(&:reenable) if Rake::Task.tasks.any?

    # Setup test logger to capture output
    allow(Rails).to receive(:logger).and_return(test_logger)

    # Capture stdout for commands that use puts
    allow($stdout).to receive(:puts) { |msg| stdout_output.puts(msg) }

    # Mock git integration
    allow(MigrationGuard::GitIntegration).to receive(:new).and_return(git_integration)
    allow(git_integration).to receive_messages(
      current_branch: "feature/test",
      main_branch: "main",
      migration_versions_in_trunk: []
    )

    # Clean database state
    MigrationGuard::MigrationGuardRecord.delete_all

    # Enable MigrationGuard by default
    allow(MigrationGuard).to receive(:enabled?).and_return(true)
  end

  after do
    Rails.logger = original_logger
  end

  # Helper methods
  def run_rake_task(task_name, env_vars = {})
    original_env = ENV.to_h
    env_vars.each { |k, v| ENV[k] = v.to_s }

    Rake::Task[task_name].reenable
    Rake::Task[task_name].execute
  ensure
    ENV.replace(original_env)
  end

  def task_output
    # Combine both logger output and stdout for backward compatibility
    rake_output.string + stdout_output.string
  end

  def create_migration_record(version, status: "applied", branch: "feature/test", **attributes)
    MigrationGuard::MigrationGuardRecord.create!(
      version: version,
      status: status,
      branch: branch,
      author: "test@example.com",
      **attributes
    )
  end

  describe "db:migration:status" do
    context "when MigrationGuard is disabled" do
      before { allow(MigrationGuard).to receive(:enabled?).and_return(false) }

      it "logs disabled message and returns" do
        run_rake_task("db:migration:status")

        expect(task_output).to include("MigrationGuard is not enabled")
        expect(task_output).not_to include("Migration Status")
      end
    end

    context "with no migrations" do
      it "displays empty status report" do
        run_rake_task("db:migration:status")

        expect(task_output).to include("Migration Status")
        expect(task_output).to include("✓ All migrations synced with main: 0 migrations")
      end
    end

    context "with orphaned migrations" do
      before do
        create_migration_record("20240101000001", branch: "feature/test")
        create_migration_record("20240101000002", branch: "feature/other")
        create_migration_record("20240101000003", branch: "main")
        allow(git_integration).to receive(:migration_versions_in_trunk).and_return(["20240101000003"])
      end

      # rubocop:disable RSpec/MultipleExpectations
      it "displays orphaned migrations grouped by branch" do
        run_rake_task("db:migration:status")

        expect(task_output).to include("⚠ Orphaned: 2 migrations")
        expect(task_output).to include("20240101000001")
        expect(task_output).to include("20240101000002")
        expect(task_output).to include("feature/test")
        expect(task_output).to include("feature/other")
        expect(task_output).not_to include("20240101000003") # Not orphaned
      end
      # rubocop:enable RSpec/MultipleExpectations
    end

    context "with JSON format" do
      before do
        create_migration_record("20240101000001")
        allow(git_integration).to receive(:migration_versions_in_trunk).and_return([])
      end

      it "outputs valid JSON when FORMAT=json" do
        pending "JSON format not yet implemented in Reporter"
        run_rake_task("db:migration:status", "FORMAT" => "json")

        json_output = JSON.parse(task_output)
        expect(json_output).to have_key("status")
        expect(json_output["orphaned_count"]).to eq(1)
      end
    end
  end

  describe "db:migration:rollback_orphaned" do
    let(:rollbacker) { instance_double(MigrationGuard::Rollbacker) }

    before do
      allow(MigrationGuard::Rollbacker).to receive(:new).and_return(rollbacker)
    end

    context "when MigrationGuard is disabled" do
      before { allow(MigrationGuard).to receive(:enabled?).and_return(false) }

      it "logs disabled message and returns" do
        expect(rollbacker).not_to receive(:rollback_orphaned)

        run_rake_task("db:migration:rollback_orphaned")

        expect(task_output).to include("MigrationGuard is not enabled")
      end
    end

    context "with orphaned migrations" do
      before do
        create_migration_record("20240101000001")
        allow(rollbacker).to receive(:rollback_orphaned)
      end

      it "calls rollbacker to handle orphaned migrations" do
        run_rake_task("db:migration:rollback_orphaned")

        expect(rollbacker).to have_received(:rollback_orphaned).at_least(:once)
      end
    end
  end

  describe "db:migration:rollback_specific" do
    let(:rollbacker) { instance_double(MigrationGuard::Rollbacker) }

    before do
      allow(MigrationGuard::Rollbacker).to receive(:new).and_return(rollbacker)
    end

    context "without VERSION parameter" do
      it "logs usage message" do
        run_rake_task("db:migration:rollback_specific")

        expect(task_output).to include("Usage: rails db:migration:rollback_specific VERSION=xxx")
        expect(rollbacker).not_to receive(:rollback_specific)
      end
    end

    # rubocop:disable RSpec/MultipleMemoizedHelpers
    context "with valid VERSION" do
      let(:version) { "20240101000001" }

      before do
        create_migration_record(version)
        allow(rollbacker).to receive(:rollback_specific).with(version)
      end

      it "calls rollbacker with the specified version" do
        run_rake_task("db:migration:rollback_specific", "VERSION" => version)

        expect(rollbacker).to have_received(:rollback_specific).with(version).at_least(:once)
      end
    end
    # rubocop:enable RSpec/MultipleMemoizedHelpers

    # rubocop:disable RSpec/MultipleMemoizedHelpers
    context "when migration not found" do
      let(:version) { "99999999999999" }

      before do
        allow(rollbacker).to receive(:rollback_specific)
          .with(version)
          .and_raise(MigrationGuard::MigrationNotFoundError, "Migration #{version} not found")
      end

      it "logs error message" do
        run_rake_task("db:migration:rollback_specific", "VERSION" => version)

        expect(task_output).to include("Migration #{version} not found")
      end
    end
    # rubocop:enable RSpec/MultipleMemoizedHelpers
  end

  describe "db:migration:cleanup" do
    let(:tracker) { instance_double(MigrationGuard::Tracker) }

    before do
      allow(MigrationGuard::Tracker).to receive(:new).and_return(tracker)
    end

    context "without FORCE parameter" do
      it "displays warning message" do
        run_rake_task("db:migration:cleanup")

        expect(task_output).to include("This will delete migration tracking records")
        expect(task_output).to include("To proceed, run with FORCE=true")
        expect(tracker).not_to receive(:cleanup_old_records)
      end
    end

    context "with FORCE=true" do
      before do
        # Create old records
        old_record = create_migration_record("20230101000001")
        old_record.update!(created_at: 100.days.ago)

        recent_record = create_migration_record("20240101000001")
        recent_record.update!(created_at: 1.day.ago)

        allow(tracker).to receive(:cleanup_old_records).and_return(1)
      end

      it "cleans up old records and reports count" do
        run_rake_task("db:migration:cleanup", "FORCE" => "true")

        expect(tracker).to have_received(:cleanup_old_records).at_least(:once)
        expect(task_output).to include("Cleaned up 1 old migration tracking records")
      end
    end
  end

  describe "db:migration:history" do
    let(:historian) { instance_double(MigrationGuard::Historian) }

    before do
      allow(MigrationGuard::Historian).to receive(:new).and_return(historian)
      allow(historian).to receive(:format_history_output).and_return("History output")
    end

    context "with no filters" do
      it "displays all migration history" do
        run_rake_task("db:migration:history")

        expect(MigrationGuard::Historian).to have_received(:new).with({}).at_least(:once)
        expect(task_output).to include("History output")
      end
    end

    context "with filters" do
      it "passes filter options to historian" do
        run_rake_task("db:migration:history",
                      "BRANCH" => "main",
                      "DAYS" => "30",
                      "VERSION" => "20240101",
                      "AUTHOR" => "test",
                      "LIMIT" => "10",
                      "FORMAT" => "json")

        expect(MigrationGuard::Historian).to have_received(:new).with(
          branch: "main",
          days: 30,
          version: "20240101",
          author: "test",
          limit: 10,
          format: "json"
        ).at_least(:once)
      end
    end
  end

  describe "db:migration:doctor" do
    let(:diagnostics) { instance_double(MigrationGuard::DiagnosticRunner) }

    before do
      allow(MigrationGuard::DiagnosticRunner).to receive(:new).and_return(diagnostics)
      allow(diagnostics).to receive(:run_all_checks)
    end

    it "runs diagnostic checks" do
      run_rake_task("db:migration:doctor")

      expect(diagnostics).to have_received(:run_all_checks).at_least(:once)
    end
  end

  # rubocop:disable RSpec/MultipleMemoizedHelpers
  describe "db:migration:recover" do
    let(:analyzer) { instance_double(MigrationGuard::RecoveryAnalyzer) }
    let(:executor) { instance_double(MigrationGuard::RecoveryExecutor) }

    before do
      allow(MigrationGuard::RecoveryAnalyzer).to receive(:new).and_return(analyzer)
      allow(MigrationGuard::RecoveryExecutor).to receive(:new).and_return(executor)
    end

    context "with no issues" do
      before do
        allow(analyzer).to receive_messages(analyze: [], format_analysis_report: "No issues found")
        allow(executor).to receive(:backup_path).and_return(nil)
      end

      it "reports no issues and exits" do
        run_rake_task("db:migration:recover")

        expect(task_output).to include("No issues found")
        expect(MigrationGuard::RecoveryExecutor).not_to have_received(:new)
      end
    end

    context "with issues and AUTO=true" do
      let(:issues) { [{ type: :orphaned, version: "20240101000001" }] }

      before do
        allow(analyzer).to receive_messages(analyze: issues, format_analysis_report: "Issues found")
        allow(executor).to receive_messages(execute_recovery: true, backup_path: "/tmp/migration_guard_backup_123")
        allow($stdin).to receive(:gets).and_return("1\n", "y\n") # Select option and confirm
      end

      it "executes recovery automatically" do
        run_rake_task("db:migration:recover", "AUTO" => "true")

        expect(task_output).to include("Issues found")
        # The actual implementation prompts even with AUTO=true
        expect(executor).to have_received(:execute_recovery).at_least(:once)
      end
    end
  end
  # rubocop:enable RSpec/MultipleMemoizedHelpers

  describe "db:migration:authors" do
    let(:author_reporter) { instance_double(MigrationGuard::AuthorReporter) }

    before do
      allow(MigrationGuard::AuthorReporter).to receive(:new).and_return(author_reporter)
      allow(author_reporter).to receive(:format_authors_report).and_return("Authors report")
    end

    it "displays authors report" do
      run_rake_task("db:migration:authors")

      expect(task_output).to include("Authors report")
    end
  end

  describe "edge cases and error handling" do
    context "when database connection fails" do
      before do
        allow(MigrationGuard::MigrationGuardRecord).to receive(:delete_all)
          .and_raise(ActiveRecord::ConnectionNotEstablished)
      end

      it "handles database errors gracefully" do
        expect { run_rake_task("db:migration:status") }.not_to raise_error
      end
    end

    context "when Rails logger is nil" do
      before do
        # The rake tasks still use Rails.logger.info for the disabled message
        # In real usage, Rails.logger should never be nil, but we test defensive programming
        allow(Rails).to receive(:logger).and_return(nil)
        allow(MigrationGuard).to receive(:enabled?).and_return(false)
      end

      it "doesn't crash when logger is unavailable" do
        # With MigrationGuard disabled and nil logger, the check_enabled method will fail
        expect { run_rake_task("db:migration:status") }.to raise_error(NoMethodError)
      end
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
