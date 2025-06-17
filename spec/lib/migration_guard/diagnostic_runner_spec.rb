# frozen_string_literal: true

require "rails_helper"

RSpec.describe MigrationGuard::DiagnosticRunner do
  let(:runner) { described_class.new }
  let(:io) { StringIO.new }

  before do
    # Disable colorization for testing
    allow(MigrationGuard::Colorizer).to receive(:colorize_output?).and_return(false)
    allow(runner).to receive(:puts) { |msg| io.puts(msg) }
    allow(runner).to receive(:print) { |msg| io.print(msg) }
  end

  describe "#run_all_checks" do
    let(:git_integration) { instance_double(MigrationGuard::GitIntegration) }
    let(:reporter) { instance_double(MigrationGuard::Reporter) }

    before do
      allow(MigrationGuard::GitIntegration).to receive(:new).and_return(git_integration)
      allow(MigrationGuard::Reporter).to receive(:new).and_return(reporter)
      allow(git_integration).to receive_messages(current_branch: "feature/test", main_branch: "main")
      allow(reporter).to receive_messages(orphaned_migrations: [], missing_migrations: {})
    end

    it "runs all diagnostic checks" do
      # Configure to make this environment "enabled" for the test
      allow(MigrationGuard.configuration).to receive_messages(enabled_environments: [:test], target_branches: ["main"])

      runner.run_all_checks

      output = io.string
      aggregate_failures do
        expect(output).to include("Running Migration Guard Diagnostics")
        expect(output).to include("✓ Database connection")
        expect(output).to include("✓ Migration guard tables")
        expect(output).to include("✓ Git repository")
        expect(output).to include("✓ Git branch detection")
        expect(output).to include("✓ Orphaned migrations")
        expect(output).to include("✓ Missing migrations")
        expect(output).to include("✓ Stuck migrations")
        expect(output).to include("✓ Environment configuration")
        expect(output).to include("Overall Status: ALL SYSTEMS OK")
      end
    end

    context "when database connection fails" do
      before do
        allow(ActiveRecord::Base.connection).to receive(:execute).and_call_original
        allow(ActiveRecord::Base.connection).to receive(:execute).with("SELECT 1").and_raise(StandardError,
                                                                                             "Connection failed")
      end

      it "reports database connection error" do
        runner.run_all_checks

        output = io.string
        aggregate_failures do
          expect(output).to include("✗ Database connection")
          expect(output).to include("Issues Found:")
          expect(output).to include("Database connection failed")
          expect(output).to include("Check your database configuration")
          expect(output).to include("Overall Status: NEEDS ATTENTION")
        end
      end
    end

    context "when migration guard tables are missing" do
      before do
        allow(MigrationGuard::MigrationGuardRecord).to receive(:table_exists?).and_return(false)
        allow(MigrationGuard::MigrationGuardRecord).to receive(:count).and_raise(StandardError, "Table missing")
      end

      it "reports missing tables error" do
        runner.run_all_checks

        output = io.string
        aggregate_failures do
          expect(output).to include("✗ Migration guard tables")
          expect(output).to include("Issues Found:")
          expect(output).to include("Migration guard tables missing")
          expect(output).to include("Run 'rails generate migration_guard:install'")
        end
      end
    end

    context "when git is not available" do
      before do
        allow(git_integration).to receive(:current_branch).and_raise(MigrationGuard::GitError, "Git not found")
        allow(git_integration).to receive(:main_branch).and_raise(MigrationGuard::GitError, "Git not found")
      end

      it "reports git integration errors" do
        runner.run_all_checks

        output = io.string
        aggregate_failures do
          expect(output).to include("✗ Git repository")
          expect(output).to include("✗ Git branch detection")
          expect(output).to include("Issues Found:")
          expect(output).to include("Git repository not found")
          expect(output).to include("Git branch detection failed")
        end
      end
    end

    context "when orphaned migrations exist" do
      let(:orphaned_migration) do
        MigrationGuard::MigrationGuardRecord.new(
          version: "20240115123456",
          created_at: 3.days.ago
        )
      end

      before do
        allow(reporter).to receive(:orphaned_migrations).and_return([orphaned_migration])
      end

      it "reports orphaned migrations" do
        runner.run_all_checks

        output = io.string
        aggregate_failures do
          expect(output).to include("✗ Orphaned migrations")
          expect(output).to include("1 found (oldest: 3 days)")
          expect(output).to include("Issues Found:")
          expect(output).to include("Orphaned migrations detected")
          expect(output).to include("Run 'rails db:migration:rollback_orphaned'")
        end
      end
    end

    context "when missing migrations exist" do
      before do
        allow(reporter).to receive(:missing_migrations).and_return({
                                                                     "main" => %w[20240101000001 20240102000002],
                                                                     "develop" => ["20240103000003"]
                                                                   })
      end

      it "reports missing migrations as warnings" do
        runner.run_all_checks

        output = io.string
        aggregate_failures do
          expect(output).to include("⚠ Missing migrations")
          expect(output).to include("3 found in: main, develop")
          expect(output).to include("Warnings:")
          expect(output).to include("Missing migrations from trunk")
          expect(output).to include("Consider running 'rails db:migrate'")
          expect(output).to include("Overall Status: OK WITH WARNINGS")
        end
      end
    end

    context "when target branches are configured" do
      before do
        allow(MigrationGuard.configuration).to receive(:target_branches).and_return(%w[main develop])
      end

      it "reports configured target branches" do
        runner.run_all_checks

        output = io.string
        expect(output).to include("✓ Target branch configuration: configured: main, develop")
      end
    end

    context "when no target branches are configured" do
      before do
        allow(MigrationGuard.configuration).to receive(:target_branches).and_return(nil)
      end

      it "reports warning about default configuration" do
        runner.run_all_checks

        output = io.string
        aggregate_failures do
          expect(output).to include("⚠ Target branch configuration")
          expect(output).to include("using default")
          expect(output).to include("Warnings:")
          expect(output).to include("No target branches configured")
        end
      end
    end

    context "when MigrationGuard is disabled in current environment" do
      before do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
      end

      it "reports environment warning" do
        runner.run_all_checks

        output = io.string
        aggregate_failures do
          expect(output).to include("⚠ Environment configuration")
          expect(output).to include("disabled in production")
          expect(output).to include("Warnings:")
          expect(output).to include("MigrationGuard disabled in current environment")
        end
      end
    end

    context "when Rails is not loaded" do
      before do
        hide_const("Rails")
      end

      it "reports Rails not loaded warning" do
        runner.run_all_checks

        output = io.string
        aggregate_failures do
          expect(output).to include("⚠ Environment configuration")
          expect(output).to include("Rails not loaded")
          expect(output).to include("Warnings:")
          expect(output).to include("Rails environment not detected")
        end
      end
    end

    context "when schema inconsistencies exist" do
      before do
        # Create a migration tracked as applied but not in schema_migrations
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240101000001",
          status: "applied",
          branch: "main"
        )

        # Add a migration to schema_migrations but not tracked
        ActiveRecord::Base.connection.execute("INSERT INTO schema_migrations (version) VALUES ('20240101000002')")

        # Create a rolled back migration that's still in schema_migrations
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240101000003",
          status: "rolled_back",
          branch: "feature"
        )
        ActiveRecord::Base.connection.execute("INSERT INTO schema_migrations (version) VALUES ('20240101000003')")
      end

      after do
        sql = "DELETE FROM schema_migrations WHERE version IN ('20240101000002', '20240101000003')"
        ActiveRecord::Base.connection.execute(sql)
      end

      it "reports schema consistency issues" do
        runner.run_all_checks

        output = io.string
        expect(output).to include("✗ Schema consistency")
        expect(output).to include("1 tracked as applied but missing from schema")
        expect(output).to include("1 rolled back but still in schema")
        expect(output).to include("1 in schema but not tracked")
      end
    end

    context "when stuck migrations exist" do
      before do
        # Create a recent rolling_back migration (should not be detected)
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240201000001",
          status: "rolling_back",
          branch: "feature/stuck",
          updated_at: 5.minutes.ago
        )

        # Create an old rolling_back migration (should be detected)
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240201000002",
          status: "rolling_back",
          branch: "feature/stuck",
          updated_at: 20.minutes.ago
        )
      end

      it "reports only migrations stuck for more than 10 minutes" do
        runner.run_all_checks

        output = io.string
        aggregate_failures do
          expect(output).to include("✗ Stuck migrations")
          expect(output).to include("1 stuck (oldest: 20m)")
          expect(output).to include("Issues Found:")
          expect(output).to include("Stuck migrations detected")
          expect(output).to include("Migration(s) stuck in rollback state: 20240201000002")
          expect(output).to include("Run 'rails db:migration:recover' to fix")
          # Make sure the recent one is not in the stuck migrations error message
          expect(output).not_to match(/Migration\(s\) stuck in rollback state:.*20240201000001/)
        end
      end
    end

    context "when no stuck migrations exist" do
      it "reports no stuck migrations found" do
        runner.run_all_checks

        output = io.string
        expect(output).to include("✓ Stuck migrations: none found")
      end
    end

    context "with custom stuck_migration_timeout" do
      before do
        allow(MigrationGuard.configuration).to receive(:stuck_migration_timeout).and_return(5)

        # Create migrations at different times
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240301000001",
          status: "rolling_back",
          branch: "feature/test",
          updated_at: 3.minutes.ago # Should NOT be detected with 5 minute timeout
        )

        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240301000002",
          status: "rolling_back",
          branch: "feature/test",
          updated_at: 7.minutes.ago # Should be detected with 5 minute timeout
        )
      end

      it "respects the configured timeout" do
        runner.run_all_checks

        output = io.string
        aggregate_failures do
          expect(output).to include("✗ Stuck migrations")
          expect(output).to include("1 stuck") # Only 1 should be detected
          expect(output).to include("Migration(s) stuck in rollback state: 20240301000002")
          expect(output).not_to match(/Migration\(s\) stuck in rollback state:.*20240301000001/)
        end
      end
    end

    context "when testing sandbox mode" do
      context "when sandbox mode is enabled" do
        before do
          allow(MigrationGuard.configuration).to receive(:sandbox_mode).and_return(true)
        end

        it "reports sandbox mode as active with warning" do
          runner.run_all_checks

          output = io.string
          aggregate_failures do
            expect(output).to include("⚠ Sandbox mode: ACTIVE (changes will be rolled back)")
            expect(output).to include("Warnings:")
            expect(output).to include("Sandbox mode is enabled")
            expect(output).to include("Migrations will be rolled back after execution")
          end
        end
      end

      context "when sandbox mode is disabled" do
        before do
          allow(MigrationGuard.configuration).to receive(:sandbox_mode).and_return(false)
        end

        it "reports sandbox mode as disabled" do
          runner.run_all_checks

          output = io.string
          expect(output).to include("✓ Sandbox mode: disabled")
        end
      end
    end
  end
end
