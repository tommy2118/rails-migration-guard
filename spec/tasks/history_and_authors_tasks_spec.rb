# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "History and authors rake tasks", type: :integration do
  let(:rake_output) { StringIO.new }
  let(:original_logger) { Rails.logger }
  let(:test_logger) { Logger.new(rake_output) }

  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  before do
    # Reset all task state properly
    Rake::Task.tasks.each do |task|
      task.reenable
      task.instance_variable_set(:@already_invoked, false)
    end
    allow(Rails).to receive(:logger).and_return(test_logger)
    allow(MigrationGuard).to receive(:enabled?).and_return(true)

    MigrationGuard::MigrationGuardRecord.delete_all
  end

  after do
    Rails.logger = original_logger
  end

  def task_output
    rake_output.string
  end

  def create_migration_history(version, **attributes)
    defaults = {
      status: "applied",
      branch: "main",
      author: "test@example.com",
      created_at: Time.current,
      metadata: {}
    }
    MigrationGuard::MigrationGuardRecord.create!(
      version: version,
      **defaults.merge(attributes)
    )
  end

  describe "db:migration:history" do
    before do
      # Create diverse migration history
      create_migration_history("20240101000001",
                               author: "alice@example.com",
                               branch: "main",
                               created_at: 7.days.ago,
                               metadata: { "direction" => "UP", "execution_time" => "2.5" })

      create_migration_history("20240102000001",
                               author: "bob@example.com",
                               branch: "feature/users",
                               created_at: 5.days.ago,
                               status: "applied",
                               metadata: { "direction" => "UP", "execution_time" => "1.2" })

      create_migration_history("20240103000001",
                               author: "bob@example.com",
                               branch: "feature/users",
                               created_at: 3.days.ago,
                               status: "rolled_back",
                               metadata: { "direction" => "DOWN", "execution_time" => "0.8" })

      create_migration_history("20240104000001",
                               author: "charlie@example.com",
                               branch: "hotfix/urgent",
                               created_at: 1.day.ago,
                               metadata: { "direction" => "UP", "execution_time" => "5.3" })

      create_migration_history("20240105000001",
                               author: "alice@example.com",
                               branch: "main",
                               created_at: 1.hour.ago,
                               metadata: { "direction" => "UP" })
    end

    context "without filters" do
      # rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
      it "displays complete migration history" do
        Rake::Task["db:migration:history"].execute

        output = task_output

        # Header
        expect(output).to include("📜 Migration History")

        # Table headers
        expect(output).to include("Timestamp")
        expect(output).to include("Version")
        expect(output).to include("Migration")
        expect(output).to include("Direction")
        expect(output).to include("Status")
        expect(output).to include("Branch")
        expect(output).to include("Author")

        # All migrations should be present
        expect(output).to include("20240101000001")
        expect(output).to include("20240102000001")
        expect(output).to include("20240103000001")
        expect(output).to include("20240104000001")
        expect(output).to include("20240105000001")

        # Status indicators
        expect(output).to include("✓ Applied")
        expect(output).to include("⤺ Rolled Back")

        # Summary statistics
        expect(output).to include("📊 Summary:")
        expect(output).to include("Total records: 5")
        expect(output).to include("Applied: 4")
        expect(output).to include("Rolled back: 1")
      end
      # rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations
    end

    context "with BRANCH filter" do
      it "shows only migrations from specified branch" do
        ENV["BRANCH"] = "feature/users"
        Rake::Task["db:migration:history"].execute

        output = task_output
        expect(output).to include("20240102000001")
        expect(output).to include("20240103000001")
        expect(output).not_to include("20240101000001") # main branch
        expect(output).not_to include("20240104000001") # hotfix branch

        expect(output).to include("Total records: 2")
      ensure
        ENV.delete("BRANCH")
      end
    end

    context "with DAYS filter" do
      it "shows only recent migrations" do
        ENV["DAYS"] = "3"
        Rake::Task["db:migration:history"].execute

        output = task_output
        expect(output).to include("20240104000001") # 1 day ago
        expect(output).to include("20240105000001") # 1 hour ago
        expect(output).not_to include("20240101000001") # 7 days ago
        expect(output).not_to include("20240102000001") # 5 days ago

        expect(output).to include("Total records: 2")
      ensure
        ENV.delete("DAYS")
      end
    end

    context "with AUTHOR filter" do
      # rubocop:disable RSpec/MultipleExpectations
      it "shows migrations by specific author" do
        ENV["AUTHOR"] = "bob"
        Rake::Task["db:migration:history"].execute

        output = task_output
        expect(output).to include("20240102000001")
        expect(output).to include("20240103000001")
        expect(output).to include("bob@example.com")
        expect(output).not_to include("alice@example.com")
        expect(output).not_to include("charlie@example.com")

        expect(output).to include("Total records: 2")
      ensure
        ENV.delete("AUTHOR")
      end
      # rubocop:enable RSpec/MultipleExpectations
    end

    context "with VERSION filter" do
      it "shows specific migration version" do
        ENV["VERSION"] = "20240103000001"
        Rake::Task["db:migration:history"].execute

        output = task_output
        expect(output).to include("20240103000001")
        expect(output).not_to include("20240101000001")
        expect(output).not_to include("20240102000001")

        expect(output).to include("Total records: 1")
      ensure
        ENV.delete("VERSION")
      end
    end

    context "with LIMIT filter" do
      # rubocop:disable RSpec/MultipleExpectations
      it "limits number of records shown" do
        ENV["LIMIT"] = "3"
        Rake::Task["db:migration:history"].execute

        output = task_output
        # Should show 3 most recent
        expect(output).to include("20240105000001")
        expect(output).to include("20240104000001")
        expect(output).to include("20240103000001")
        expect(output).not_to include("20240102000001")
        expect(output).not_to include("20240101000001")

        expect(output).to include("Total records: 3")
        expect(output).to include("Active Filters:")
        expect(output).to include("Limit: 3")
      ensure
        ENV.delete("LIMIT")
      end
      # rubocop:enable RSpec/MultipleExpectations
    end

    context "with combined filters" do
      it "applies multiple filters correctly" do
        ENV["BRANCH"] = "main"
        ENV["DAYS"] = "10"
        ENV["AUTHOR"] = "alice"
        Rake::Task["db:migration:history"].execute

        output = task_output
        # Should only show Alice's migrations on main branch within 10 days
        expect(output).to include("20240101000001")
        expect(output).to include("20240105000001")
        expect(output).not_to include("20240102000001") # Different branch
        expect(output).not_to include("20240104000001") # Different author

        expect(output).to include("Total records: 2")
      ensure
        %w[BRANCH DAYS AUTHOR].each { |key| ENV.delete(key) }
      end
    end

    context "with no matching records" do
      it "shows appropriate message" do
        ENV["BRANCH"] = "nonexistent"
        Rake::Task["db:migration:history"].execute

        output = task_output
        expect(output).to include("No migration records found")
      ensure
        ENV.delete("BRANCH")
      end
    end
  end

  describe "db:migration:authors" do
    before do
      # Create migrations by different authors
      # Alice - 4 migrations
      create_migration_history("20240101000001", author: "alice@example.com", created_at: 10.days.ago)
      create_migration_history("20240102000001", author: "alice@example.com", created_at: 8.days.ago)
      create_migration_history("20240103000001", author: "alice@example.com", created_at: 5.days.ago,
                                                 status: "rolled_back")
      create_migration_history("20240104000001", author: "alice@example.com", created_at: 2.days.ago)

      # Bob - 2 migrations
      create_migration_history("20240105000001", author: "bob@example.com", created_at: 7.days.ago)
      create_migration_history("20240106000001", author: "bob@example.com", created_at: 3.days.ago)

      # Charlie - 1 migration
      create_migration_history("20240107000001", author: "charlie@example.com", created_at: 1.day.ago)

      # System - 1 migration (no author)
      create_migration_history("20240108000001", author: nil, created_at: 4.days.ago)
    end

    # rubocop:disable RSpec/MultipleExpectations
    it "displays author statistics report" do
      Rake::Task["db:migration:authors"].execute

      output = task_output

      # Header
      expect(output).to include("👥 Migration Authors Report")

      # Table headers
      expect(output).to include("Author")
      expect(output).to include("Total")
      expect(output).to include("Applied")
      expect(output).to include("Rolled Back")
      expect(output).to include("Latest Migration")

      # Author rankings (should be sorted by count descending)
      expect(output).to include("alice@example.com")
      expect(output).to include("bob@example.com")
      expect(output).to include("charlie@example.com")

      # Verify counts - looking at the actual output format
      expect(output).to match(/alice@example.com\s+4\s+3/)
      expect(output).to match(/bob@example.com\s+2\s+2/)
      expect(output).to match(/charlie@example.com\s+1\s+1/)

      # Summary
      expect(output).to include("📊 Authors Summary:")
      expect(output).to include("Total authors: 3") # Only counting those with emails
      expect(output).to include("Total tracked migrations: 7") # Not counting nil author
      expect(output).to include("Average per author:")
    end
    # rubocop:enable RSpec/MultipleExpectations

    context "with no migration records" do
      before do
        MigrationGuard::MigrationGuardRecord.delete_all
      end

      it "shows appropriate message" do
        Rake::Task["db:migration:authors"].execute

        output = task_output
        expect(output).to include("No migration authors found")
      end
    end
  end

  describe "db:migration:check_branch_change" do
    it "executes branch change detection" do
      detector = instance_double(MigrationGuard::BranchChangeDetector)
      expect(MigrationGuard::BranchChangeDetector).to receive(:new).once.and_return(detector)
      expect(detector).to receive(:check_branch_change).once.with("abc123", "def456", "1")

      Rake::Task["db:migration:check_branch_change"].invoke("abc123", "def456", "1")
    end
  end

  describe "edge cases" do
    context "with very long author names" do
      before do
        create_migration_history("20240101000001",
                                 author: "very.long.email.address.that.might.overflow@example-company.com")
      end

      it "handles long author names in display" do
        Rake::Task["db:migration:authors"].execute

        output = task_output
        # Should truncate or handle gracefully
        expect(output).to include("example-company.com")
      end
    end

    context "with special characters in metadata" do
      before do
        create_migration_history("20240101000001",
                                 metadata: {
                                   "direction" => "UP",
                                   "special" => "Test with 'quotes' and \"double quotes\"",
                                   "unicode" => "Test with émojis 🚀"
                                 })
      end

      it "handles special characters in output" do
        Rake::Task["db:migration:history"].execute

        output = task_output
        expect(output).to include("20240101000001")
        # Should not crash with special characters
      end
    end
  end
end
