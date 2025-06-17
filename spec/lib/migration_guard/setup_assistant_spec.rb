# frozen_string_literal: true

require "rails_helper"
require_relative "../../../lib/migration_guard/setup_assistant"

RSpec.describe MigrationGuard::SetupAssistant do
  let(:assistant) { described_class.new }
  let(:io) { StringIO.new }
  let(:reporter) { instance_double(MigrationGuard::Reporter) }
  let(:git_integration) { instance_double(MigrationGuard::GitIntegration) }

  before do
    # Disable colorization for testing
    allow(MigrationGuard::Colorizer).to receive(:colorize_output?).and_return(false)

    # Mock output methods to capture output
    allow(assistant).to receive(:puts) { |msg| io.puts(msg) }
    allow(assistant).to receive(:print) { |msg| io.print(msg) }

    # Mock dependencies
    allow(assistant).to receive(:instance_variable_get).with(:@reporter).and_return(reporter)
    allow(assistant).to receive(:instance_variable_get).with(:@git_integration).and_return(git_integration)

    # Set the instance variables directly
    assistant.instance_variable_set(:@reporter, reporter)
    assistant.instance_variable_set(:@git_integration, git_integration)

    # Mock basic git integration
    allow(git_integration).to receive_messages(current_branch: "feature/test", main_branch: "main")

    # Mock basic reporter methods
    allow(reporter).to receive_messages(orphaned_migrations: [], missing_migrations: [])

    # Mock database connection
    allow(ActiveRecord::Base.connection).to receive_messages(execute: true, select_values: [])
    allow(MigrationGuard::MigrationGuardRecord).to receive_messages(table_exists?: true, pluck: [])
  end

  describe "#run_setup" do
    context "when environment is properly configured" do
      before do
        allow(MigrationGuard).to receive(:enabled?).and_return(true)
        # Mock stdin to avoid interactive prompts in tests
        allow($stdin).to receive(:gets).and_return("n\n")
      end

      it "runs complete setup analysis" do
        assistant.run_setup

        output = io.string
        aggregate_failures do
          expect(output).to include("Welcome to Rails Migration Guard Setup!")
          expect(output).to include("Analyzing your environment...")
          expect(output).to include("Analyzing migration state...")
          expect(output).to include("Summary")
          expect(output).to include("Everything looks good!")
        end
      end

      it "shows positive summary when everything is configured" do
        assistant.run_setup

        output = io.string
        aggregate_failures do
          expect(output).to include("Everything looks good!")
          expect(output).to include("Track migrations across branches")
          expect(output).to include("Detect orphaned migrations")
          expect(output).to include("Coordinate with your team")
        end
      end

      it "shows helpful commands when there are recommendations" do
        # Add an orphaned migration to trigger recommendations
        # rubocop:disable RSpec/VerifiedDoubles
        orphaned_migration = double("MigrationGuardRecord",
                                    version: "20240101000001",
                                    branch: "feature/old",
                                    status: "applied")
        # rubocop:enable RSpec/VerifiedDoubles
        allow(reporter).to receive(:orphaned_migrations).and_return([orphaned_migration])

        assistant.run_setup

        output = io.string
        aggregate_failures do
          expect(output).to include("Helpful Commands")
          expect(output).to include("rails db:migration:status")
          expect(output).to include("rails db:migration:doctor")
          expect(output).to include("Happy coding!")
        end
      end
    end

    context "when Migration Guard is not enabled" do
      before do
        allow(MigrationGuard).to receive(:enabled?).and_return(false)
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("test"))
        allow($stdin).to receive(:gets).and_return("n\n")
      end

      it "reports Migration Guard as not enabled" do
        assistant.run_setup

        output = io.string
        aggregate_failures do
          expect(output).to include("Migration Guard installation")
          expect(output).to include("not enabled in test")
          expect(output).to include("issue(s) found that need attention")
        end
      end
    end

    context "when database connection fails" do
      before do
        allow(MigrationGuard).to receive(:enabled?).and_return(true)
        # Mock the check_database_connection method directly instead of the connection
        allow(assistant).to receive(:check_database_connection) do
          assistant.send(:add_issue, "Database connection failed", "Error: Connection failed")
          assistant.send(:print_check, "Database connection", :error, "failed")
        end
        allow($stdin).to receive(:gets).and_return("n\n")
      end

      it "reports database connection error" do
        assistant.run_setup

        output = io.string
        aggregate_failures do
          expect(output).to include("Database connection")
          expect(output).to include("failed")
          expect(output).to include("Connection failed")
        end
      end
    end

    context "when git repository has issues" do
      before do
        allow(MigrationGuard).to receive(:enabled?).and_return(true)
        allow(git_integration).to receive(:current_branch).and_raise(MigrationGuard::GitError.new("Not a git repo"))
        allow($stdin).to receive(:gets).and_return("n\n")
      end

      it "reports git repository error" do
        assistant.run_setup

        output = io.string
        aggregate_failures do
          expect(output).to include("Git repository")
          expect(output).to include("issue detected")
          expect(output).to include("Not a git repo")
        end
      end
    end

    context "when orphaned migrations exist" do
      let(:orphaned_migration) do
        # rubocop:disable RSpec/VerifiedDoubles
        double("MigrationGuardRecord",
               version: "20240101000001",
               branch: "feature/old",
               status: "applied")
        # rubocop:enable RSpec/VerifiedDoubles
      end

      before do
        allow(MigrationGuard).to receive(:enabled?).and_return(true)
        allow(reporter).to receive(:orphaned_migrations).and_return([orphaned_migration])
        allow($stdin).to receive(:gets).and_return("n\n")
      end

      it "reports orphaned migrations and suggests rollback" do
        assistant.run_setup

        output = io.string
        aggregate_failures do
          expect(output).to include("Orphaned migrations")
          expect(output).to include("1 found from branches: feature/old")
          expect(output).to include("Recommended Actions")
          expect(output).to include("rails db:migration:rollback_orphaned")
        end
      end
    end

    context "when missing migrations exist" do
      before do
        allow(MigrationGuard).to receive(:enabled?).and_return(true)
        allow(reporter).to receive(:missing_migrations).and_return(["20240101000002"])
        allow($stdin).to receive(:gets).and_return("n\n")
      end

      it "reports missing migrations and suggests migrate" do
        assistant.run_setup

        output = io.string
        aggregate_failures do
          expect(output).to include("Missing migrations")
          expect(output).to include("1 found in main branch")
          expect(output).to include("Recommended Actions")
          expect(output).to include("rails db:migrate")
        end
      end
    end

    context "with multi-branch missing migrations" do
      before do
        allow(MigrationGuard).to receive(:enabled?).and_return(true)
        allow(reporter).to receive(:missing_migrations).and_return({
                                                                     "main" => ["20240101000002"],
                                                                     "develop" => ["20240101000003"]
                                                                   })
        allow($stdin).to receive(:gets).and_return("n\n")
      end

      it "reports missing migrations from multiple branches" do
        assistant.run_setup

        output = io.string
        aggregate_failures do
          expect(output).to include("Missing migrations")
          expect(output).to include("2 found in: main, develop")
          expect(output).to include("Recommended Actions")
          expect(output).to include("rails db:migrate")
        end
      end
    end

    context "when user accepts interactive fixes" do
      before do
        allow(MigrationGuard).to receive(:enabled?).and_return(true)
        allow(reporter).to receive(:missing_migrations).and_return(["20240101000002"])
        allow($stdin).to receive(:gets).and_return("y\n")
        allow(assistant).to receive(:system).and_return(true)
      end

      it "executes suggested migrations" do
        expect(assistant).to receive(:system).with("rails db:migrate")
        assistant.run_setup

        output = io.string
        expect(output).to include("Running: Run missing migrations: rails db:migrate")
      end
    end

    context "when schema inconsistencies exist" do
      before do
        allow(MigrationGuard).to receive(:enabled?).and_return(true)
        allow(ActiveRecord::Base.connection).to receive(:select_values)
          .and_return(%w[20240101000001 20240101000002])
        allow(MigrationGuard::MigrationGuardRecord).to receive(:pluck)
          .and_return(["20240101000001"])
        allow($stdin).to receive(:gets).and_return("n\n")
      end

      it "reports untracked migrations in schema" do
        assistant.run_setup

        output = io.string
        aggregate_failures do
          expect(output).to include("Schema consistency")
          expect(output).to include("1 pre-existing migrations detected")
          expect(output).to include("This is normal if Migration Guard was added to an existing project")
        end
      end
    end

    context "when on main branch" do
      before do
        allow(MigrationGuard).to receive(:enabled?).and_return(true)
        allow(git_integration).to receive(:current_branch).and_return("main")
        allow($stdin).to receive(:gets).and_return("n\n")
      end

      it "shows positive status for being on main branch" do
        assistant.run_setup

        output = io.string
        expect(output).to include("Branch status: on main branch")
      end
    end

    context "when on feature branch" do
      before do
        allow(MigrationGuard).to receive(:enabled?).and_return(true)
        allow(git_integration).to receive(:current_branch).and_return("feature/new-feature")
        allow($stdin).to receive(:gets).and_return("n\n")
      end

      it "shows info about feature branch development" do
        assistant.run_setup

        output = io.string
        aggregate_failures do
          expect(output).to include("Branch status: on feature branch: feature/new-feature")
          expect(output).to include("This is normal for feature development")
        end
      end
    end
  end
end
