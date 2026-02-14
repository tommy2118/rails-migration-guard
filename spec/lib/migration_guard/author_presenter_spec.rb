# frozen_string_literal: true

require "rails_helper"

RSpec.describe MigrationGuard::AuthorPresenter do
  subject(:presenter) { described_class.new }

  before do
    allow(MigrationGuard::Colorizer).to receive(:colorize_output?).and_return(false)
  end

  describe "#format_authors_report" do
    context "with author data" do
      let(:authors_data) do
        [
          {
            author: "alice@example.com",
            total: 5,
            applied: 3,
            orphaned: 1,
            rolled_back: 1,
            synced: 0,
            latest_migration: Time.zone.local(2024, 6, 15, 10, 30)
          },
          {
            author: "bob@example.com",
            total: 3,
            applied: 2,
            orphaned: 0,
            rolled_back: 1,
            synced: 0,
            latest_migration: Time.zone.local(2024, 5, 10, 8, 0)
          }
        ]
      end

      it "includes header with branch name" do
        result = presenter.format_authors_report(authors_data, "feature/auth")

        expect(result).to include("Migration Authors Report (feature/auth)")
      end

      it "includes table header columns" do
        result = presenter.format_authors_report(authors_data, "main")

        aggregate_failures do
          expect(result).to include("Author")
          expect(result).to include("Total")
          expect(result).to include("Applied")
          expect(result).to include("Orphaned")
          expect(result).to include("Rolled Back")
          expect(result).to include("Latest Migration")
        end
      end

      it "includes author rows with counts" do
        result = presenter.format_authors_report(authors_data, "main")

        aggregate_failures do
          expect(result).to include("alice@example.com")
          expect(result).to include("bob@example.com")
          expect(result).to include("2024-06-15 10:30")
        end
      end

      it "includes summary statistics" do
        result = presenter.format_authors_report(authors_data, "main")

        aggregate_failures do
          expect(result).to include("Total authors: 2")
          expect(result).to include("Total tracked migrations: 8")
          expect(result).to include("Most active: alice@example.com (5 migrations)")
        end
      end
    end

    context "with empty data" do
      it "returns no-authors message with setup hints" do
        result = presenter.format_authors_report([], "main")

        aggregate_failures do
          expect(result).to include("No migration authors found")
          expect(result).to include("config.track_author = true")
          expect(result).to include("git config user.email")
        end
      end
    end

    context "with pre-sorted author data" do
      let(:authors_data) do
        [
          { author: "top@example.com", total: 10, applied: 10, orphaned: 0, rolled_back: 0, synced: 0,
            latest_migration: Time.zone.local(2024, 1, 1) },
          { author: "low@example.com", total: 2, applied: 2, orphaned: 0, rolled_back: 0, synced: 0,
            latest_migration: Time.zone.local(2024, 1, 1) }
        ]
      end

      it "displays higher total count first" do
        result = presenter.format_authors_report(authors_data, "main")

        top_pos = result.index("top@example.com")
        low_pos = result.index("low@example.com")
        expect(top_pos).to be < low_pos
      end
    end
  end
end
