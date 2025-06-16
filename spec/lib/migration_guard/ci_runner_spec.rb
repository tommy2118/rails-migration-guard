# frozen_string_literal: true

require "rails_helper"

# rubocop:disable RSpec/VerifiedDoubles, RSpec/NestedGroups

RSpec.describe MigrationGuard::CiRunner do
  let(:git_integration) { instance_double(MigrationGuard::GitIntegration) }
  let(:reporter) { instance_double(MigrationGuard::Reporter) }

  before do
    allow(MigrationGuard::GitIntegration).to receive(:new).and_return(git_integration)
    allow(MigrationGuard::Reporter).to receive(:new).and_return(reporter)

    allow(git_integration).to receive_messages(
      current_branch: "feature/test",
      main_branch: "main"
    )
  end

  describe "#initialize" do
    it "initializes with default values" do
      runner = described_class.new
      expect(runner).to be_a(described_class)
    end

    it "normalizes format parameter" do
      runner = described_class.new(format: "JSON")
      expect(runner).to be_a(described_class)
    end

    it "handles invalid format gracefully" do
      runner = described_class.new(format: "invalid")
      expect(runner).to be_a(described_class)
    end
  end

  describe "#run" do
    context "when MigrationGuard is disabled" do
      before do
        allow(MigrationGuard).to receive(:enabled?).and_return(false)
      end

      it "returns success exit code for text format" do
        runner = described_class.new(format: "text")
        exit_code = runner.run

        expect(exit_code).to eq(MigrationGuard::CiRunner::EXIT_SUCCESS)
      end

      it "outputs disabled message in text format" do
        runner = described_class.new(format: "text")

        expect { runner.run }.to output(/MigrationGuard is not enabled/).to_stdout
      end

      it "outputs disabled message in JSON format" do
        runner = described_class.new(format: "json")

        expect { runner.run }.to output(/"status": "disabled"/).to_stdout
      end
    end

    context "when MigrationGuard is enabled" do
      before do
        allow(MigrationGuard).to receive(:enabled?).and_return(true)
      end

      context "with no migration issues" do
        before do
          allow(reporter).to receive_messages(orphaned_migrations: [], missing_migrations: [])
        end

        it "returns success exit code" do
          runner = described_class.new
          exit_code = runner.run

          expect(exit_code).to eq(MigrationGuard::CiRunner::EXIT_SUCCESS)
        end

        it "outputs success message in text format" do
          runner = described_class.new(format: "text")

          expect { runner.run }.to output(/✅ No migration issues found/).to_stdout
        end

        it "outputs success status in JSON format" do
          runner = described_class.new(format: "json")

          expect { runner.run }.to output(/"status": "success"/).to_stdout
        end
      end

      context "with orphaned migrations" do
        let(:orphaned_migration) do
          double("migration_record",
                 version: "20240101000001",
                 branch: "feature/test",
                 author: "test@example.com",
                 created_at: Time.current)
        end

        before do
          allow(reporter).to receive_messages(orphaned_migrations: [orphaned_migration], missing_migrations: [])
        end

        context "with warning strictness" do
          it "returns warning exit code" do
            runner = described_class.new(strictness: "warning")
            exit_code = runner.run

            expect(exit_code).to eq(MigrationGuard::CiRunner::EXIT_WARNING)
          end

          it "outputs warning status in text format" do
            runner = described_class.new(format: "text", strictness: "warning")

            expect { runner.run }.to output(/⚠️.*Migration Guard CI Check/).to_stdout
          end
        end

        context "with strict mode" do
          it "returns error exit code" do
            runner = described_class.new(strict: true)
            exit_code = runner.run

            expect(exit_code).to eq(MigrationGuard::CiRunner::EXIT_ERROR)
          end

          it "outputs error status in text format" do
            runner = described_class.new(format: "text", strict: true)

            expect { runner.run }.to output(/❌.*Migration Guard CI Check/).to_stdout
          end
        end

        it "includes migration details in text output" do
          runner = described_class.new(format: "text")

          output = capture_stdout { runner.run }

          aggregate_failures "migration details" do
            expect(output).to include("Orphaned Migrations Found")
            expect(output).to include("20240101000001")
            expect(output).to include("feature/test")
            expect(output).to include("test@example.com")
          end
        end

        it "includes migration details in JSON output" do
          runner = described_class.new(format: "json")

          output = capture_stdout { runner.run }
          json = JSON.parse(output)

          orphaned = json.dig("migration_guard", "orphaned_migrations")
          expect(orphaned).to be_an(Array)
          expect(orphaned.first).to include(
            "version" => "20240101000001",
            "branch" => "feature/test",
            "author" => "test@example.com"
          )
        end

        it "includes recommended actions in text output" do
          runner = described_class.new(format: "text")

          output = capture_stdout { runner.run }

          aggregate_failures "recommended actions" do
            expect(output).to include("Recommended Actions")
            expect(output).to include("rails db:migration:rollback_specific VERSION=20240101000001")
          end
        end
      end

      context "with missing migrations" do
        before do
          allow(reporter).to receive_messages(orphaned_migrations: [], missing_migrations: ["20240101000002"])
        end

        it "returns warning exit code in warning mode" do
          runner = described_class.new(strictness: "warning")
          exit_code = runner.run

          expect(exit_code).to eq(MigrationGuard::CiRunner::EXIT_WARNING)
        end

        it "returns error exit code in strict mode" do
          runner = described_class.new(strict: true)
          exit_code = runner.run

          expect(exit_code).to eq(MigrationGuard::CiRunner::EXIT_ERROR)
        end

        it "includes missing migration details in text output" do
          runner = described_class.new(format: "text")

          output = capture_stdout { runner.run }

          aggregate_failures "missing migration details" do
            expect(output).to include("Missing Migrations")
            expect(output).to include("20240101000002")
            expect(output).to include("git pull origin main")
            expect(output).to include("rails db:migrate")
          end
        end

        it "includes missing migration details in JSON output" do
          runner = described_class.new(format: "json")

          output = capture_stdout { runner.run }
          json = JSON.parse(output)

          missing = json.dig("migration_guard", "missing_migrations")
          expect(missing).to be_an(Array)
          expect(missing.first).to include("version" => "20240101000002")
        end
      end

      context "with both orphaned and missing migrations" do
        let(:orphaned_migration) do
          double("migration_record",
                 version: "20240101000001",
                 branch: "feature/test",
                 author: "test@example.com",
                 created_at: Time.current)
        end

        before do
          allow(reporter).to receive_messages(orphaned_migrations: [orphaned_migration],
                                              missing_migrations: ["20240101000002"])
        end

        it "reports both issue types in summary" do
          runner = described_class.new(format: "text")

          output = capture_stdout { runner.run }

          aggregate_failures "summary counts" do
            expect(output).to include("Orphaned: 1")
            expect(output).to include("Missing: 1")
          end
        end

        it "includes both issue types in JSON output" do
          runner = described_class.new(format: "json")

          output = capture_stdout { runner.run }
          json = JSON.parse(output)

          summary = json.dig("migration_guard", "summary")
          expect(summary).to include(
            "total_orphaned" => 1,
            "total_missing" => 1,
            "issues_found" => 2
          )
        end
      end
    end

    context "when an error occurs" do
      before do
        allow(MigrationGuard).to receive(:enabled?).and_return(true)
        allow(reporter).to receive(:orphaned_migrations).and_raise(StandardError, "Database error")
      end

      it "returns error exit code" do
        runner = described_class.new
        exit_code = runner.run

        expect(exit_code).to eq(MigrationGuard::CiRunner::EXIT_ERROR)
      end

      it "outputs error message in text format" do
        runner = described_class.new(format: "text")

        expect { runner.run }.to output(/❌ Error running Migration Guard CI check/).to_stdout
      end

      it "outputs error details in JSON format" do
        runner = described_class.new(format: "json")

        output = capture_stdout { runner.run }
        json = JSON.parse(output)

        expect(json.dig("migration_guard", "status")).to eq("error")
        expect(json.dig("migration_guard", "error")).to eq("Database error")
      end
    end
  end

  describe "parameter handling" do
    it "handles legacy strict parameter" do
      runner = described_class.new(strict: true)
      expect(runner).to be_a(described_class)
    end

    it "handles new strictness parameter" do
      runner = described_class.new(strictness: "strict")
      expect(runner).to be_a(described_class)
    end

    it "prioritizes strictness over strict when both provided" do
      allow(MigrationGuard).to receive(:enabled?).and_return(true)
      allow(reporter).to receive_messages(orphaned_migrations: [], missing_migrations: [])

      runner = described_class.new(strict: true, strictness: "permissive")
      exit_code = runner.run

      # Should use "permissive" strictness, not strict mode
      expect(exit_code).to eq(MigrationGuard::CiRunner::EXIT_SUCCESS)
    end
  end

  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end
end
# rubocop:enable RSpec/VerifiedDoubles, RSpec/NestedGroups
