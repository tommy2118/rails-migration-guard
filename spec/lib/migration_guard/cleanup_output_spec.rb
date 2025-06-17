# frozen_string_literal: true

require "rails_helper"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "MigrationGuard cleanup command output" do
  # rubocop:enable RSpec/DescribeClass
  let(:rake_tasks) { MigrationGuard::RakeTasks }
  let(:io) { StringIO.new }
  let(:tracker) { instance_double(MigrationGuard::Tracker) }

  before do
    allow(MigrationGuard).to receive(:enabled?).and_return(true)
    allow(MigrationGuard::Colorizer).to receive(:colorize_output?).and_return(false)
    allow($stdout).to receive(:puts) { |msg| io.puts(msg) }
    allow(MigrationGuard::Tracker).to receive(:new).and_return(tracker)
  end

  describe "#cleanup" do
    context "without force flag" do
      let(:config) { instance_double(MigrationGuard::Configuration, cleanup_after_days: 30) }

      before do
        allow(MigrationGuard).to receive(:configuration).and_return(config)
      end

      it "displays warning message and requires FORCE=true" do
        # Need ENV to return nil for FORCE
        allow(ENV).to receive(:[]).with("FORCE").and_return(nil)

        rake_tasks.cleanup(force: false)

        output = io.string
        expect(output).to include("This will delete migration tracking records older than 30 days.")
        expect(output).to include("To proceed, run with FORCE=true")
      end
    end

    context "with force flag" do
      before do
        allow(tracker).to receive(:cleanup_old_records).and_return(5)
      end

      it "executes cleanup and displays success message" do
        rake_tasks.cleanup(force: true)

        output = io.string
        expect(output).to include("✓ Cleaned up 5 old migration tracking records")
        expect(tracker).to have_received(:cleanup_old_records)
      end
    end

    context "with FORCE environment variable" do
      before do
        allow(ENV).to receive(:[]).with("FORCE").and_return("true")
        allow(tracker).to receive(:cleanup_old_records).and_return(3)
      end

      it "executes cleanup when FORCE=true in environment" do
        rake_tasks.cleanup(force: false)

        output = io.string
        expect(output).to include("✓ Cleaned up 3 old migration tracking records")
        expect(tracker).to have_received(:cleanup_old_records)
      end
    end

    context "when no records are cleaned up" do
      before do
        allow(tracker).to receive(:cleanup_old_records).and_return(0)
      end

      it "displays zero count message" do
        rake_tasks.cleanup(force: true)

        output = io.string
        expect(output).to include("✓ Cleaned up 0 old migration tracking records")
      end
    end
  end
end
