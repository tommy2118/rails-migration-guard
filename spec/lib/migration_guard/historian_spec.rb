# frozen_string_literal: true

require "rails_helper"

RSpec.describe MigrationGuard::Historian do
  let(:historian) { described_class.new }
  let(:git_integration) { instance_double(MigrationGuard::GitIntegration) }

  before do
    # Clean up any existing records
    MigrationGuard::MigrationGuardRecord.delete_all

    # Mock git integration
    allow(MigrationGuard::GitIntegration).to receive(:new).and_return(git_integration)
    allow(git_integration).to receive_messages(current_branch: "feature/test", main_branch: "main",
                                               migration_versions_in_trunk: [])
  end

  describe "#initialize" do
    it "accepts options for filtering" do
      options = { branch: "main", days: 7, version: "123", limit: 10 }
      historian = described_class.new(options)

      expect(historian.instance_variable_get(:@branch_filter)).to eq("main")
      expect(historian.instance_variable_get(:@days_filter)).to eq(7)
      expect(historian.instance_variable_get(:@version_filter)).to eq("123")
      expect(historian.instance_variable_get(:@limit)).to eq(10)
    end

    it "sets default limit" do
      expect(historian.instance_variable_get(:@limit)).to eq(50)
    end

    it "defaults to table format" do
      expect(historian.instance_variable_get(:@format)).to eq("table")
    end

    context "with invalid options" do
      it "raises error for unsupported format" do
        expect do
          described_class.new(format: "invalid")
        end.to raise_error(ArgumentError, /Unsupported format/)
      end

      it "raises error for invalid limit" do
        expect do
          described_class.new(limit: 0)
        end.to raise_error(ArgumentError, /Limit must be between/)
      end

      it "raises error for invalid days filter" do
        expect do
          described_class.new(days: 400)
        end.to raise_error(ArgumentError, /Days filter must be between/)
      end
    end
  end

  describe "#migration_history" do
    # rubocop:disable RSpec/IndexedLet
    let!(:migration1) do
      MigrationGuard::MigrationGuardRecord.create!(
        version: "20240101000001",
        branch: "main",
        author: "developer@example.com",
        status: "applied",
        metadata: { "direction" => "UP" },
        created_at: 2.days.ago
      )
    end

    let!(:migration2) do
      MigrationGuard::MigrationGuardRecord.create!(
        version: "20240102000001",
        branch: "feature/test",
        author: "developer@example.com",
        status: "rolled_back",
        metadata: { "direction" => "DOWN" },
        created_at: 1.day.ago
      )
    end
    # rubocop:enable RSpec/IndexedLet

    it "returns migrations ordered by created_at desc" do
      records = historian.migration_history
      expect(records.first).to eq(migration2)
      expect(records.second).to eq(migration1)
    end

    it "respects limit" do
      historian = described_class.new(limit: 1)
      records = historian.migration_history
      expect(records.count).to eq(1)
    end

    context "with branch filter" do
      it "filters by branch" do
        historian = described_class.new(branch: "main")
        records = historian.migration_history
        expect(records.count).to eq(1)
        expect(records.first.branch).to eq("main")
      end
    end

    context "with days filter" do
      it "filters by days" do
        historian = described_class.new(days: 2)
        records = historian.migration_history
        expect(records.count).to eq(1)
        expect(records.first).to eq(migration2)
      end
    end

    context "with version filter" do
      it "filters by version" do
        historian = described_class.new(version: "20240101000001")
        records = historian.migration_history
        expect(records.count).to eq(1)
        expect(records.first.version).to eq("20240101000001")
      end
    end

    context "with author filter" do
      it "filters by author" do
        historian = described_class.new(author: "developer@example.com")
        records = historian.migration_history
        expect(records.count).to eq(2)
        expect(records.all? { |r| r.author&.include?("developer@example.com") }).to be true
      end

      it "filters by partial author match" do
        historian = described_class.new(author: "developer")
        records = historian.migration_history
        expect(records.count).to eq(2)
        expect(records.all? { |r| r.author&.include?("developer") }).to be true
      end
    end
  end

  describe "#format_history_output" do
    # rubocop:disable RSpec/LetSetup
    let!(:migration1) do
      MigrationGuard::MigrationGuardRecord.create!(
        version: "20240101000001",
        branch: "main",
        author: "developer@example.com",
        status: "applied",
        metadata: { "direction" => "UP", "execution_time" => "2.5" }
      )
    end

    context "with table format" do
      it "includes table headers" do
        output = historian.format_history_output

        aggregate_failures do
          expect(output).to include("📜 Migration History")
          expect(output).to include("Timestamp")
          expect(output).to include("Version")
          expect(output).to include("Migration")
          expect(output).to include("Direction")
          expect(output).to include("Status")
          expect(output).to include("Branch")
          expect(output).to include("Author")
        end
      end

      it "includes migration data" do
        output = historian.format_history_output
        expect(output).to include("20240101000001")
        expect(output).to include("main")
        expect(output).to include("developer@example") # Allow for truncation
      end

      it "includes summary statistics" do
        output = historian.format_history_output
        expect(output).to include("📊 Summary:")
        expect(output).to include("Total records: 1")
        expect(output).to include("  Applied: 1")
      end

      it "shows no records message when empty" do
        MigrationGuard::MigrationGuardRecord.delete_all
        output = historian.format_history_output
        expect(output).to include("No migration records found")
      end
    end

    context "with json format" do
      let(:historian) { described_class.new(format: "json") }

      it "returns valid JSON" do
        output = historian.format_history_output
        parsed = JSON.parse(output)

        expect(parsed).to have_key("summary")
        expect(parsed).to have_key("filters")
        expect(parsed).to have_key("history")
        expect(parsed["history"]).to be_an(Array)
        expect(parsed["history"].first).to include("version" => "20240101000001")
      end
    end

    context "with csv format" do
      let(:historian) { described_class.new(format: "csv") }

      it "returns CSV data or error message when csv gem unavailable" do
        output = historian.format_history_output

        # CSV might not be available in test environment
        if output.include?("CSV format requires")
          expect(output).to include("CSV format requires the 'csv' gem")
        else
          lines = output.split("\n")
          expect(lines.first).to include("Timestamp,Version,Migration")
          expect(lines.second).to include("20240101000001")
        end
      end
    end
    # rubocop:enable RSpec/LetSetup
  end

  describe "#statistics" do
    # rubocop:disable RSpec/LetSetup
    let!(:applied_migration) do
      MigrationGuard::MigrationGuardRecord.create!(
        version: "20240101000001",
        status: "applied",
        branch: "main"
      )
    end

    let!(:rolled_back_migration) do
      MigrationGuard::MigrationGuardRecord.create!(
        version: "20240102000001",
        status: "rolled_back",
        branch: "feature/test"
      )
    end

    let!(:orphaned_migration) do
      MigrationGuard::MigrationGuardRecord.create!(
        version: "20240103000001",
        status: "orphaned",
        branch: "feature/old"
      )
    end

    it "calculates correct statistics" do
      stats = historian.statistics

      aggregate_failures do
        expect(stats[:total]).to eq(3)
        expect(stats[:applied]).to eq(1)
        expect(stats[:rolled_back]).to eq(1)
        expect(stats[:orphaned]).to eq(1)
        expect(stats[:branches]).to contain_exactly("main", "feature/test", "feature/old")
        expect(stats[:date_range]).to match(/\d{4}-\d{2}-\d{2} to \d{4}-\d{2}-\d{2}/)
      end
    end
    # rubocop:enable RSpec/LetSetup
  end

  describe "integration with MigrationGuardRecord model enhancements" do
    let!(:migration) do
      MigrationGuard::MigrationGuardRecord.create!(
        version: "20240101123456",
        status: "applied",
        metadata: { "direction" => "UP", "execution_time" => "1.5" }
      )
    end

    describe "model methods" do
      it "returns correct direction" do
        expect(migration.direction).to eq("UP")
      end

      it "returns formatted execution time" do
        expect(migration.execution_time).to eq("1.5s")
      end

      it "returns display status with icons" do
        expect(migration.display_status).to eq("✓ Applied")
      end

      it "handles rolled back status" do
        migration.update!(status: "rolled_back")
        expect(migration.display_status).to eq("⤺ Rolled Back")
      end

      it "handles orphaned status" do
        migration.update!(status: "orphaned")
        expect(migration.display_status).to eq("⚠ Orphaned")
      end
    end

    describe "model scopes" do
      let!(:recent_migration) do
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240102000001",
          status: "applied",
          created_at: 1.day.ago
        )
      end

      let!(:old_migration) do
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240103000001",
          status: "applied",
          created_at: 10.days.ago
        )
      end

      it "filters by days with within_days scope" do
        recent = MigrationGuard::MigrationGuardRecord.within_days(2)
        expect(recent).to include(recent_migration)
        expect(recent).not_to include(old_migration)
      end

      it "orders by created_at with history_ordered scope" do
        ordered = MigrationGuard::MigrationGuardRecord.history_ordered
        expect(ordered.first.created_at).to be >= ordered.last.created_at
      end
    end
  end

  describe "rake task integration" do
    # rubocop:disable RSpec/LetSetup
    let!(:migration) do
      MigrationGuard::MigrationGuardRecord.create!(
        version: "20240101000001",
        branch: "main",
        status: "applied"
      )
    end

    # rubocop:disable RSpec/AnyInstance
    it "calls historian from rake tasks" do
      expect_any_instance_of(described_class).to receive(:format_history_output).and_return("History output")
      allow(MigrationGuard).to receive(:enabled?).and_return(true)
      allow($stdout).to receive(:puts)
      MigrationGuard::RakeTasks.history
    end

    it "passes options to historian" do
      options = { branch: "main", days: 7 }
      expect(described_class).to receive(:new).with(options).and_call_original
      allow(MigrationGuard).to receive(:enabled?).and_return(true)
      MigrationGuard::RakeTasks.history(options)
    end
    # rubocop:enable RSpec/AnyInstance, RSpec/LetSetup
  end
end
