# frozen_string_literal: true

require "rails_helper"

RSpec.describe MigrationGuard::AuthorReporter do
  let(:author_reporter) { described_class.new }
  let(:git_integration) { instance_double(MigrationGuard::GitIntegration) }

  before do
    # Clean up any existing records
    MigrationGuard::MigrationGuardRecord.delete_all

    # Mock git integration
    allow(MigrationGuard::GitIntegration).to receive(:new).and_return(git_integration)
    allow(git_integration).to receive_messages(
      current_branch: "feature/test",
      current_author: "testuser@example.com"
    )
  end

  describe "#initialize" do
    it "creates a git integration instance" do
      expect(MigrationGuard::GitIntegration).to receive(:new)
      described_class.new
    end
  end

  describe "#format_authors_report" do
    context "with no migration records" do
      it "returns a no authors message" do
        output = author_reporter.format_authors_report

        aggregate_failures do
          expect(output).to include("No migration authors found")
          expect(output).to include("Author tracking is disabled")
          expect(output).to include("git config user.email")
        end
      end
    end

    context "with migration records" do
      # rubocop:disable RSpec/LetSetup
      let!(:developer1_migrations) do
        [
          MigrationGuard::MigrationGuardRecord.create!(
            version: "20240101000001",
            author: "developer1@example.com",
            status: "applied",
            branch: "main",
            created_at: 3.days.ago
          ),
          MigrationGuard::MigrationGuardRecord.create!(
            version: "20240102000001",
            author: "developer1@example.com",
            status: "orphaned",
            branch: "feature/old",
            created_at: 2.days.ago
          )
        ]
      end

      let!(:developer2_migrations) do
        [
          MigrationGuard::MigrationGuardRecord.create!(
            version: "20240103000001",
            author: "developer2@example.com",
            status: "applied",
            branch: "main",
            created_at: 1.day.ago
          ),
          MigrationGuard::MigrationGuardRecord.create!(
            version: "20240104000001",
            author: "developer2@example.com",
            status: "rolled_back",
            branch: "feature/test",
            created_at: 1.hour.ago
          ),
          MigrationGuard::MigrationGuardRecord.create!(
            version: "20240105000001",
            author: "developer2@example.com",
            status: "synced",
            branch: "main",
            created_at: 30.minutes.ago
          )
        ]
      end
      # rubocop:enable RSpec/LetSetup

      it "includes report header with branch info" do
        output = author_reporter.format_authors_report

        aggregate_failures do
          expect(output).to include("👥 Migration Authors Report")
          expect(output).to include("(feature/test)")
        end
      end

      it "includes table headers" do
        output = author_reporter.format_authors_report

        aggregate_failures do
          expect(output).to include("Author")
          expect(output).to include("Total")
          expect(output).to include("Applied")
          expect(output).to include("Orphaned")
          expect(output).to include("Rolled Back")
          expect(output).to include("Latest Migration")
        end
      end

      it "displays authors sorted by total migrations" do
        output = author_reporter.format_authors_report

        # developer2 should be first (3 migrations) before developer1 (2 migrations)
        dev2_index = output.index("developer2@example.com")
        dev1_index = output.index("developer1@example.com")
        expect(dev2_index).to be < dev1_index
      end

      it "displays correct migration counts" do
        output = author_reporter.format_authors_report

        # Check developer2's counts (3 total: 1 applied, 1 rolled_back, 1 synced)
        aggregate_failures do
          expect(output).to match(/developer2@example\.com.*3.*1.*0.*1/)
          expect(output).to match(/developer1@example\.com.*2.*1.*1.*0/)
        end
      end

      it "includes summary statistics" do
        output = author_reporter.format_authors_report

        aggregate_failures do
          expect(output).to include("📊 Authors Summary:")
          expect(output).to include("Total authors: 2")
          expect(output).to include("Total tracked migrations: 5")
          expect(output).to include("Most active: developer2@example.com (3 migrations)")
          expect(output).to include("Average per author: 2.5")
        end
      end

      it "shows current user's rank when available" do
        allow(git_integration).to receive(:current_author).and_return("developer1@example.com")
        output = author_reporter.format_authors_report

        expect(output).to include("Your rank: #2 (2 migrations)")
      end

      it "handles current user with no contributions" do
        allow(git_integration).to receive(:current_author).and_return("newuser@example.com")
        output = author_reporter.format_authors_report

        expect(output).to include("Your contributions: No tracked migrations found")
      end

      it "handles git integration errors gracefully" do
        allow(git_integration).to receive(:current_author).and_raise(StandardError, "Git error")
        output = author_reporter.format_authors_report

        # Should not include user rank section when git fails
        expect(output).not_to include("Your rank:")
        expect(output).not_to include("Your contributions:")
      end

      it "truncates long author names" do
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240106000001",
          author: "very.long.email.address.that.exceeds.thirty.characters@example.com",
          status: "applied",
          branch: "main"
        )

        output = author_reporter.format_authors_report
        expect(output).to include("very.long.email.address.tha...")
      end

      it "handles nil and empty authors" do
        # Create records with nil/empty authors (should be filtered out)
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240107000001",
          author: nil,
          status: "applied",
          branch: "main"
        )
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240108000001",
          author: "",
          status: "applied",
          branch: "main"
        )

        output = author_reporter.format_authors_report

        # Should still show only the 2 developers with valid emails
        expect(output).to include("Total authors: 2")
        expect(output).to include("Total tracked migrations: 5")
      end
    end

    context "with branch info unavailable" do
      it "shows unknown branch in header" do
        # Add some test data so we get a report, not the no authors message
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240101000001",
          author: "test@example.com",
          status: "applied",
          branch: "main"
        )

        allow(git_integration).to receive(:current_branch).and_raise(StandardError, "No git")
        output = author_reporter.format_authors_report

        expect(output).to include("(unknown)")
      end
    end
  end

  describe "#collect_authors_data" do
    # rubocop:disable RSpec/LetSetup
    let!(:test_migrations) do
      [
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240101000001",
          author: "dev1@example.com",
          status: "applied",
          created_at: 2.days.ago
        ),
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240102000001",
          author: "dev1@example.com",
          status: "orphaned",
          created_at: 1.day.ago
        ),
        MigrationGuard::MigrationGuardRecord.create!(
          version: "20240103000001",
          author: "dev2@example.com",
          status: "applied",
          created_at: 1.hour.ago
        )
      ]
    end
    # rubocop:enable RSpec/LetSetup

    it "returns authors data sorted by activity" do
      data = author_reporter.collect_authors_data

      aggregate_failures do
        expect(data).to be_an(Array)
        expect(data.size).to eq(2)

        # Both have 2 total migrations (dev1) and 1 (dev2), so dev1 should be first
        expect(data.first[:author]).to eq("dev1@example.com")
        expect(data.first[:total]).to eq(2)
        expect(data.first[:applied]).to eq(1)
        expect(data.first[:orphaned]).to eq(1)

        expect(data.second[:author]).to eq("dev2@example.com")
        expect(data.second[:total]).to eq(1)
        expect(data.second[:applied]).to eq(1)
      end
    end

    it "handles authors with same migration count sorted by latest activity" do
      # Create another migration for dev2 to tie the count
      MigrationGuard::MigrationGuardRecord.create!(
        version: "20240104000001",
        author: "dev2@example.com",
        status: "rolled_back",
        created_at: 30.minutes.ago
      )

      data = author_reporter.collect_authors_data

      # Now both have 2 migrations, dev2 should be first due to more recent activity
      aggregate_failures do
        expect(data.first[:author]).to eq("dev2@example.com")
        expect(data.first[:total]).to eq(2)
        expect(data.second[:author]).to eq("dev1@example.com")
        expect(data.second[:total]).to eq(2)
      end
    end

    it "excludes records with nil or empty authors" do
      MigrationGuard::MigrationGuardRecord.create!(
        version: "20240105000001",
        author: nil,
        status: "applied"
      )
      MigrationGuard::MigrationGuardRecord.create!(
        version: "20240106000001",
        author: "",
        status: "applied"
      )

      data = author_reporter.collect_authors_data
      expect(data.size).to eq(2) # Still only dev1 and dev2
    end
  end

  describe "private methods" do
    describe "#truncate_string" do
      it "returns string unchanged if within length limit" do
        result = author_reporter.send(:truncate_string, "short", 30)
        expect(result).to eq("short")
      end

      it "truncates string that exceeds length limit" do
        long_string = "this_is_a_very_long_string_that_exceeds_thirty_characters"
        result = author_reporter.send(:truncate_string, long_string, 30)
        expect(result).to eq("this_is_a_very_long_string_...")
        expect(result.length).to eq(30)
      end
    end

    describe "#current_user_email" do
      it "returns current author from git integration" do
        allow(git_integration).to receive(:current_author).and_return("user@example.com")
        result = author_reporter.send(:current_user_email)
        expect(result).to eq("user@example.com")
      end

      it "returns nil when git integration fails" do
        allow(git_integration).to receive(:current_author).and_raise(StandardError, "Git error")
        result = author_reporter.send(:current_user_email)
        expect(result).to be_nil
      end
    end
  end
end
