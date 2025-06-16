# frozen_string_literal: true

require "rails_helper"

RSpec.describe MigrationGuard::PostMigrationChecker do
  let(:checker) { described_class.new }
  let(:reporter) { instance_double(MigrationGuard::Reporter) }
  
  before do
    allow(MigrationGuard::Reporter).to receive(:new).and_return(reporter)
    allow(MigrationGuard).to receive(:enabled?).and_return(true)
  end

  describe "#check_and_warn" do
    context "when warn_after_migration is enabled" do
      before do
        MigrationGuard.configuration.warn_after_migration = true
      end

      context "with orphaned migrations" do
        let(:orphaned_migrations) do
          [
            { version: "20240115123456", branch: "feature/test", status: "applied" },
            { version: "20240116123456", branch: "feature/other", status: "applied" }
          ]
        end

        before do
          allow(reporter).to receive(:orphaned_migrations).and_return(orphaned_migrations)
        end

        it "outputs a warning message" do
          expect { checker.check_and_warn }.to output(/Migration Guard Warning/).to_stderr
        end

        it "lists all orphaned migrations" do
          expect { checker.check_and_warn }.to output(/20240115123456.*feature\/test/).to_stderr
          expect { checker.check_and_warn }.to output(/20240116123456.*feature\/other/).to_stderr
        end

        it "shows the correct count" do
          expect { checker.check_and_warn }.to output(/2 migrations that are not in the main branch/).to_stderr
        end

        it "provides suggestions" do
          output = capture_stderr { checker.check_and_warn }
          expect(output).to include("Commit these migrations to your branch")
          expect(output).to include("rails db:migration:rollback_orphaned")
          expect(output).to include("rails db:migration:status")
        end
      end

      context "with no orphaned migrations" do
        before do
          allow(reporter).to receive(:orphaned_migrations).and_return([])
        end

        it "does not output anything" do
          expect { checker.check_and_warn }.not_to output.to_stderr
        end
      end
    end

    context "when warn_after_migration is disabled" do
      before do
        MigrationGuard.configuration.warn_after_migration = false
        allow(reporter).to receive(:orphaned_migrations).and_return([{ version: "123", branch: "test" }])
      end

      it "does not check for orphaned migrations" do
        expect(reporter).not_to receive(:orphaned_migrations)
        checker.check_and_warn
      end

      it "does not output anything" do
        expect { checker.check_and_warn }.not_to output.to_stderr
      end
    end

    context "when MigrationGuard is disabled" do
      before do
        allow(MigrationGuard).to receive(:enabled?).and_return(false)
        MigrationGuard.configuration.warn_after_migration = true
      end

      it "does not check for orphaned migrations" do
        expect(reporter).not_to receive(:orphaned_migrations)
        checker.check_and_warn
      end
    end
  end

  private

  def capture_stderr
    original_stderr = $stderr
    $stderr = StringIO.new
    yield
    $stderr.string
  ensure
    $stderr = original_stderr
  end
end