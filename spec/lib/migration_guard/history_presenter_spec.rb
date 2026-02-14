# frozen_string_literal: true

require "rails_helper"

RSpec.describe MigrationGuard::HistoryPresenter do
  subject(:presenter) { described_class.new }

  before do
    allow(MigrationGuard::Colorizer).to receive(:colorize_output?).and_return(false)
  end

  let(:record_struct) do
    Struct.new(
      :created_at, :version, :migration_file_name, :direction,
      :status, :branch, :author, :execution_time, :metadata, :display_status
    )
  end

  let(:records) do
    [
      record_struct.new(
        Time.zone.local(2024, 6, 15, 10, 30, 0),
        "20240615103000",
        "create_users",
        "UP",
        "applied",
        "main",
        "alice@example.com",
        "0.5s",
        {},
        "Applied"
      ),
      record_struct.new(
        Time.zone.local(2024, 6, 16, 14, 0, 0),
        "20240616140000",
        "add_email_to_users",
        "DOWN",
        "rolled_back",
        "feature/email",
        "bob@example.com",
        "0.3s",
        {},
        "Rolled Back"
      )
    ]
  end

  let(:statistics_proc) do
    lambda { |_records|
      {
        total: 2,
        applied: 1,
        rolled_back: 1,
        orphaned: 0,
        branches: %w[main feature/email],
        date_range: "2024-06-15 to 2024-06-16"
      }
    }
  end

  describe "#format_table_output" do
    context "with records" do
      let(:active_filters) { {} }

      it "includes header, table rows, and summary" do
        result = presenter.format_table_output(records, statistics_proc, false, active_filters)

        aggregate_failures do
          expect(result).to include("Migration History")
          expect(result).to include("Timestamp")
          expect(result).to include("Version")
          expect(result).to include("20240615103000")
          expect(result).to include("create_users")
          expect(result).to include("alice@example.com")
          expect(result).to include("Total records: 2")
          expect(result).to include("-" * 140)
        end
      end
    end

    context "with active filters" do
      let(:active_filters) { { branch: "main", days: 30 } }

      it "includes Active Filters section" do
        result = presenter.format_table_output(records, statistics_proc, true, active_filters)

        aggregate_failures do
          expect(result).to include("Active Filters:")
          expect(result).to include("Branch: main")
          expect(result).to include("Days: 30")
        end
      end
    end

    context "with no records and filters applied" do
      it "returns filter-specific no-records message" do
        result = presenter.format_table_output([], statistics_proc, true, {})

        expect(result).to include("No migration records found for the specified filters")
      end
    end

    context "with no records and no filters" do
      it "returns generic no-records message" do
        result = presenter.format_table_output([], statistics_proc, false, {})

        aggregate_failures do
          expect(result).to include("No migration records found")
          expect(result).not_to include("for the specified filters")
        end
      end
    end
  end

  describe "#format_json_output" do
    it "returns valid JSON with expected keys" do
      active_filters = { branch: "main" }
      statistics = { total: 2 }

      json_string = presenter.format_json_output(records, statistics, active_filters)
      parsed = JSON.parse(json_string)

      aggregate_failures do
        expect(parsed).to have_key("summary")
        expect(parsed).to have_key("filters")
        expect(parsed).to have_key("history")
        expect(parsed["history"].size).to eq(2)
        expect(parsed["history"].first).to have_key("version")
        expect(parsed["history"].first).to have_key("timestamp")
        expect(parsed["history"].first).to have_key("branch")
      end
    end
  end

  describe "#format_csv_output" do
    it "returns CSV content or graceful error when csv gem unavailable" do
      result = presenter.format_csv_output(records)

      expect(result).to satisfy("contain CSV data or fallback message") do |value|
        value.include?("20240615103000") || value.include?("CSV format requires the 'csv' gem")
      end
    end
  end
end
