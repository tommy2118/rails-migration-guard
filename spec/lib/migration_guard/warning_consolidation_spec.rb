# frozen_string_literal: true

require "rails_helper"

# rubocop:disable RSpec/SpecFilePathFormat, RSpec/DescribeMethod
RSpec.describe MigrationGuard::WarningCollector, "warning consolidation" do
  # rubocop:enable RSpec/SpecFilePathFormat, RSpec/DescribeMethod
  let(:reporter) { instance_double(MigrationGuard::Reporter) }

  before do
    allow(MigrationGuard).to receive(:enabled?).and_return(true)
    allow(MigrationGuard::Reporter).to receive(:new).and_return(reporter)
    allow(reporter).to receive(:orphaned_migrations).and_return([
                                                                  { version: "20240101000001", branch: "feature/test" }
                                                                ])

    # Reset warning collector state
    described_class.reset!
  end

  after do
    described_class.reset!
  end

  describe "warning frequency behavior" do
    describe "with :each mode" do
      before do
        allow(MigrationGuard.configuration).to receive_messages(warning_frequency: :each, warn_after_migration: true)
      end

      it "shows warnings after each migration" do
        described_class.start_batch

        # First migration
        described_class.increment_migration_count
        expect(described_class.should_show_individual_warnings?).to be true

        # Second migration
        described_class.increment_migration_count
        expect(described_class.should_show_individual_warnings?).to be true

        # No summary should be shown
        expect(MigrationGuard::WarningDisplay).not_to receive(:display_summary)
        described_class.end_batch
      end
    end

    describe "with :once mode" do
      before do
        allow(MigrationGuard.configuration).to receive_messages(warning_frequency: :once, warn_after_migration: true)
      end

      it "never shows individual warnings" do
        described_class.start_batch

        # First migration
        described_class.increment_migration_count
        expect(described_class.should_show_individual_warnings?).to be false

        # Second migration
        described_class.increment_migration_count
        expect(described_class.should_show_individual_warnings?).to be false

        # Summary should be shown
        expect(MigrationGuard::WarningDisplay).to receive(:display_summary)
        described_class.end_batch
      end
    end

    describe "with :smart mode" do
      before do
        allow(MigrationGuard.configuration).to receive_messages(warning_frequency: :smart, warn_after_migration: true)
      end

      context "with single migration" do
        it "shows individual warning for first migration only" do
          described_class.start_batch

          # First migration should show warnings
          described_class.increment_migration_count
          expect(described_class.should_show_individual_warnings?).to be true

          # If warnings were shown, mark them as shown
          described_class.mark_warnings_shown

          # No summary should be shown (already showed individual warning)
          expect(MigrationGuard::WarningDisplay).not_to receive(:display_summary)
          described_class.end_batch
        end
      end

      context "with multiple migrations" do
        it "shows individual warning for first, then consolidates" do
          described_class.start_batch

          # First migration
          described_class.increment_migration_count
          expect(described_class.should_show_individual_warnings?).to be true
          described_class.mark_warnings_shown

          # Second migration - no individual warning
          described_class.increment_migration_count
          expect(described_class.should_show_individual_warnings?).to be false

          # Summary should be shown for multiple migrations
          expect(MigrationGuard::WarningDisplay).to receive(:display_summary)
          described_class.end_batch
        end

        it "shows summary if no individual warnings were shown" do
          described_class.start_batch

          # Simulate multiple migrations without showing individual warnings
          described_class.increment_migration_count
          described_class.increment_migration_count

          # Don't mark warnings as shown

          # Summary should be shown
          expect(MigrationGuard::WarningDisplay).to receive(:display_summary)
          described_class.end_batch
        end
      end
    end

    describe "with :summary mode" do
      before do
        allow(MigrationGuard.configuration).to receive_messages(warning_frequency: :summary, warn_after_migration: true)
      end

      it "never shows individual warnings" do
        described_class.start_batch

        # First migration
        described_class.increment_migration_count
        expect(described_class.should_show_individual_warnings?).to be false

        # Always shows summary
        expect(MigrationGuard::WarningDisplay).to receive(:display_summary)
        described_class.end_batch
      end
    end
  end
end
