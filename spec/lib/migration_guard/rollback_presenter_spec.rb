# frozen_string_literal: true

require "rails_helper"

RSpec.describe MigrationGuard::RollbackPresenter do
  subject(:presenter) { described_class.new }

  before do
    allow(MigrationGuard::Colorizer).to receive(:colorize_output?).and_return(false)
  end

  let(:migration_struct) { Struct.new(:version, :branch) }

  describe "#display_no_orphaned_migrations" do
    it "prints no orphaned message" do
      expect { presenter.display_no_orphaned_migrations }
        .to output(/No orphaned migrations found/).to_stdout
    end
  end

  describe "#display_orphaned_list" do
    it "prints count and version with branch for each migration" do
      orphaned = [
        migration_struct.new("20240101000001", "feature/old"),
        migration_struct.new("20240102000002", "feature/stale")
      ]

      output = capture_stdout { presenter.display_orphaned_list(orphaned) }

      aggregate_failures do
        expect(output).to include("Found 2 orphaned migrations")
        expect(output).to include("20240101000001 - feature/old")
        expect(output).to include("20240102000002 - feature/stale")
      end
    end
  end

  describe "#display_orphaned_list_simple" do
    it "prints count and version only" do
      orphaned = [migration_struct.new("20240101000001", "feature/old")]

      output = capture_stdout { presenter.display_orphaned_list_simple(orphaned) }

      aggregate_failures do
        expect(output).to include("Found 1 orphaned migration")
        expect(output).to include("20240101000001")
      end
    end
  end

  describe "#display_rollback_progress" do
    it "prints rolling back message with version" do
      expect { presenter.display_rollback_progress("20240101000001") }
        .to output(/Rolling back 20240101000001/).to_stdout
    end
  end

  describe "#display_rollback_success" do
    it "prints checkmark and pluralized count" do
      expect { presenter.display_rollback_success(3) }
        .to output(/Successfully rolled back 3 migrations/).to_stdout
    end

    it "uses singular for 1 migration" do
      expect { presenter.display_rollback_success(1) }
        .to output(/Successfully rolled back 1 migration\b/).to_stdout
    end
  end

  describe "#display_specific_rollback_success" do
    it "prints checkmark and version" do
      expect { presenter.display_specific_rollback_success("20240101000001") }
        .to output(/Successfully rolled back 20240101000001/).to_stdout
    end
  end

  describe "#display_already_rolled_back" do
    it "prints warning with version" do
      expect { presenter.display_already_rolled_back("20240101000001") }
        .to output(/Migration 20240101000001 is already rolled back/).to_stdout
    end
  end

  describe "#display_rollback_error" do
    it "prints error with version and message" do
      output = capture_stdout { presenter.display_rollback_error("20240101000001", "table not found") }

      aggregate_failures do
        expect(output).to include("Rollback failed for migration 20240101000001")
        expect(output).to include("table not found")
      end
    end
  end

  describe "#display_batch_rollback_error" do
    it "prints error with version and message" do
      expect { presenter.display_batch_rollback_error("20240101000001", "connection lost") }
        .to output(/Failed to roll back 20240101000001: connection lost/).to_stdout
    end
  end

  describe "#display_batch_rollback_results" do
    context "when all succeeded" do
      it "prints all-success message" do
        expect { presenter.display_batch_rollback_results(3, 0) }
          .to output(/All orphaned migrations rolled back successfully/).to_stdout
      end
    end

    context "with failures" do
      it "prints success and failure counts" do
        expect { presenter.display_batch_rollback_results(2, 1) }
          .to output(/Rolled back 2 migration\(s\) with 1 failure\(s\)/).to_stdout
      end
    end
  end

  private

  def capture_stdout
    output = StringIO.new
    original_stdout = $stdout
    $stdout = output
    yield
    output.string
  ensure
    $stdout = original_stdout
  end
end
