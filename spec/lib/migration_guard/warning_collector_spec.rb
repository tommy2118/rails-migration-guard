# frozen_string_literal: true

require "rails_helper"

RSpec.describe MigrationGuard::WarningCollector do
  describe ".reset!" do
    it "resets all state" do
      described_class.increment_migration_count
      described_class.start_batch

      described_class.reset!

      aggregate_failures do
        expect(described_class.migration_count).to eq(0)
        expect(described_class.batch_active?).to be false
      end
    end
  end

  describe ".start_batch" do
    before { described_class.reset! }

    it "initializes batch tracking" do
      described_class.start_batch

      aggregate_failures do
        expect(described_class.batch_active?).to be true
        expect(described_class.migration_count).to eq(0)
      end
    end

    it "respects warn_after_migration configuration" do
      allow(MigrationGuard.configuration).to receive(:warn_after_migration).and_return(false)

      described_class.start_batch
      described_class.increment_migration_count

      expect { described_class.end_batch }.not_to output.to_stderr
    end
  end

  describe ".increment_migration_count" do
    before { described_class.reset! }

    it "increments the count" do
      expect { described_class.increment_migration_count }
        .to change(described_class, :migration_count).from(0).to(1)

      expect { described_class.increment_migration_count }
        .to change(described_class, :migration_count).from(1).to(2)
    end
  end

  describe ".should_show_individual_warnings?" do
    before do
      described_class.reset!
      allow(MigrationGuard.configuration).to receive(:warning_frequency).and_return(frequency)
    end

    context "when not in a batch" do
      let(:frequency) { :once }

      it "returns true" do
        expect(described_class.should_show_individual_warnings?).to be true
      end
    end

    context "when in a batch" do
      before { described_class.start_batch }

      context "with frequency :each" do
        let(:frequency) { :each }

        it "always returns true" do
          described_class.increment_migration_count
          expect(described_class.should_show_individual_warnings?).to be true

          described_class.increment_migration_count
          expect(described_class.should_show_individual_warnings?).to be true
        end
      end

      context "with frequency :once" do
        let(:frequency) { :once }

        it "always returns false" do
          described_class.increment_migration_count
          expect(described_class.should_show_individual_warnings?).to be false

          described_class.increment_migration_count
          expect(described_class.should_show_individual_warnings?).to be false
        end
      end

      context "with frequency :smart" do
        let(:frequency) { :smart }

        it "returns true for single migration" do
          described_class.increment_migration_count
          expect(described_class.should_show_individual_warnings?).to be true
        end

        it "returns false for multiple migrations" do
          described_class.increment_migration_count
          described_class.increment_migration_count
          expect(described_class.should_show_individual_warnings?).to be false
        end
      end
    end
  end

  describe ".end_batch" do
    let(:reporter) { instance_double(MigrationGuard::Reporter) }
    let(:colorizer) { MigrationGuard::Colorizer }

    before do
      described_class.reset!
      allow(MigrationGuard::Reporter).to receive(:new).and_return(reporter)
      allow(MigrationGuard.configuration).to receive(:warn_after_migration).and_return(true)
    end

    context "when not in a batch" do
      it "does nothing" do
        expect { described_class.end_batch }.not_to output.to_stderr
      end
    end

    context "when in a batch with no migrations" do
      it "does nothing" do
        described_class.start_batch
        expect { described_class.end_batch }.not_to output.to_stderr
      end
    end

    context "when in a batch with migrations but no orphaned ones" do
      before do
        allow(reporter).to receive(:orphaned_migrations).and_return([])
      end

      it "does not display summary" do
        described_class.start_batch
        described_class.increment_migration_count

        expect { described_class.end_batch }.not_to output.to_stderr
      end
    end

    context "when in a batch with migrations and orphaned ones" do
      let(:orphaned_migrations) do
        [
          { version: "20240101000001", branch: "feature/test-1" },
          { version: "20240101000002", branch: "feature/test-2" }
        ]
      end

      before do
        allow(reporter).to receive(:orphaned_migrations).and_return(orphaned_migrations)
      end

      it "displays consolidated summary" do
        described_class.start_batch
        2.times { described_class.increment_migration_count }

        output = capture_stderr { described_class.end_batch }

        aggregate_failures do
          expect(output).to include("Migration Guard Summary")
          expect(output).to include("Successfully ran 2 migration(s)")
          expect(output).to include("20240101000001")
          expect(output).to include("20240101000002")
          expect(output).to include("rails db:migration:rollback_orphaned")
          expect(output).to include("rails db:migration:status")
        end
      end

      it "limits display to configured maximum" do
        orphaned = (1..15).map do |i|
          { version: "2024010100000#{i}", branch: "feature/test-#{i}" }
        end
        allow(reporter).to receive(:orphaned_migrations).and_return(orphaned)

        described_class.start_batch
        described_class.increment_migration_count

        output = capture_stderr { described_class.end_batch }

        aggregate_failures do
          expect(output).to include("20240101000001")
          expect(output).to include("202401010000010")
          expect(output).not_to include("202401010000011")
          expect(output).to include("... and 5 more")
        end
      end

      it "respects custom max_warnings_display configuration" do
        allow(MigrationGuard.configuration).to receive(:max_warnings_display).and_return(5)
        orphaned = (1..10).map do |i|
          { version: "2024010100000#{i}", branch: "feature/test-#{i}" }
        end
        allow(reporter).to receive(:orphaned_migrations).and_return(orphaned)

        described_class.start_batch
        described_class.increment_migration_count

        output = capture_stderr { described_class.end_batch }

        aggregate_failures do
          expect(output).to include("20240101000001")
          expect(output).to include("20240101000005")
          expect(output).not_to include("20240101000006")
          expect(output).to include("... and 5 more")
        end
      end
    end

    context "when warnings are disabled" do
      let(:orphaned_migrations) { [{ version: "20240101000001", branch: "feature/test-1" }] }

      before do
        allow(reporter).to receive(:orphaned_migrations).and_return(orphaned_migrations)
      end

      it "does not display summary" do
        allow(MigrationGuard.configuration).to receive(:warn_after_migration).and_return(false)

        described_class.start_batch
        described_class.increment_migration_count

        expect { described_class.end_batch }.not_to output.to_stderr
      end
    end

    it "always resets state after ending batch" do
      allow(reporter).to receive(:orphaned_migrations).and_return([])

      described_class.start_batch
      described_class.increment_migration_count

      described_class.end_batch

      aggregate_failures do
        expect(described_class.batch_active?).to be false
        expect(described_class.migration_count).to eq(0)
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
