# frozen_string_literal: true

require "rails_helper"

RSpec.describe MigrationGuard::Tracker do
  let(:tracker) { described_class.new }

  describe "#track_migration" do
    subject(:track) { tracker.track_migration("20240115123456", direction) }

    let(:direction) { :up }

    context "when enabled in development" do
      before do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
        allow(MigrationGuard).to receive(:enabled?).and_return(true)
        # Ensure logger doesn't interfere with tests
        allow(MigrationGuard::Logger).to receive(:debug)
        allow(MigrationGuard::Logger).to receive(:info)
        allow(MigrationGuard::Logger).to receive(:error)
      end

      context "when running migration up" do
        it "creates a tracking record" do
          expect { track }.to change(MigrationGuard::MigrationGuardRecord, :count).by(1)
        end

        it "records the migration as applied" do
          track
          record = MigrationGuard::MigrationGuardRecord.last
          expect(record.version).to eq("20240115123456")
          expect(record.status).to eq("applied")
        end


        it "records the current branch" do
          allow(tracker).to receive(:current_branch).and_return("feature/new-stuff")

          track

          record = MigrationGuard::MigrationGuardRecord.last
          expect(record.branch).to eq("feature/new-stuff")
        end

        it "records the author when configured" do
          allow(MigrationGuard.configuration).to receive(:track_author).and_return(true)
          allow(tracker).to receive(:current_author).and_return("developer@example.com")

          track

          record = MigrationGuard::MigrationGuardRecord.last
          expect(record.author).to eq("developer@example.com")
        end

        it "does not record author when not configured" do
          allow(MigrationGuard.configuration).to receive(:track_author).and_return(false)

          expect { track }.to change(MigrationGuard::MigrationGuardRecord, :count).by(1)
          
          record = MigrationGuard::MigrationGuardRecord.last
          expect(record).not_to be_nil
          expect(record.author).to be_nil
        end
      end

      context "when running migration down with existing record" do
        let(:direction) { :down }

        before do
          MigrationGuard::MigrationGuardRecord.create!(
            version: "20240115123456",
            status: "applied",
            branch: "feature/test"
          )
        end

        it "updates the status to rolled_back" do
          track
          record = MigrationGuard::MigrationGuardRecord.find_by(version: "20240115123456")
          expect(record.status).to eq("rolled_back")
        end

        it "does not create a new record" do
          expect { track }.not_to change(MigrationGuard::MigrationGuardRecord, :count)
        end
      end

      context "when running migration down without existing record" do
        let(:direction) { :down }

        it "creates a new record with rolled_back status" do
          expect { track }.to change(MigrationGuard::MigrationGuardRecord, :count).by(1)

          record = MigrationGuard::MigrationGuardRecord.last
          expect(record.status).to eq("rolled_back")
        end
      end

      context "with duplicate tracking" do
        before do
          MigrationGuard::MigrationGuardRecord.create!(
            version: "20240115123456",
            status: "applied",
            branch: "main"
          )
        end

        it "does not create duplicate records" do
          expect { track }.not_to change(MigrationGuard::MigrationGuardRecord, :count)
        end
      end
    end

    context "when disabled" do
      before do
        allow(MigrationGuard).to receive(:enabled?).and_return(false)
      end

      it "does not create a tracking record" do
        expect { track }.not_to change(MigrationGuard::MigrationGuardRecord, :count)
      end

      it "returns nil" do
        expect(track).to be_nil
      end
    end

    context "when in production" do
      before do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
      end

      it "does not create a tracking record" do
        expect { track }.not_to change(MigrationGuard::MigrationGuardRecord, :count)
      end
    end
  end

  describe "#current_branch" do
    it "returns the current git branch" do
      allow(tracker).to receive(:`)
        .with("git rev-parse --abbrev-ref HEAD 2>/dev/null")
        .and_return("feature/my-branch\n")

      expect(tracker.current_branch).to eq("feature/my-branch")
    end

    it "returns 'unknown' when git is not available" do
      allow(tracker).to receive(:`).with("git rev-parse --abbrev-ref HEAD 2>/dev/null").and_return("")

      expect(tracker.current_branch).to eq("unknown")
    end
  end

  describe "#current_author" do
    it "returns the git user email" do
      allow(tracker).to receive(:`).with("git config user.email 2>/dev/null").and_return("developer@example.com\n")

      expect(tracker.current_author).to eq("developer@example.com")
    end

    it "returns 'unknown' when git user is not configured" do
      allow(tracker).to receive(:`).with("git config user.email 2>/dev/null").and_return("")

      expect(tracker.current_author).to eq("unknown")
    end
  end

  describe "#cleanup_old_records" do
    let!(:old_record) do
      MigrationGuard::MigrationGuardRecord.create!(
        version: "20230101000000",
        status: "rolled_back",
        created_at: 45.days.ago
      )
    end

    let!(:recent_record) do
      MigrationGuard::MigrationGuardRecord.create!(
        version: "20240101000000",
        status: "rolled_back",
        created_at: 5.days.ago
      )
    end

    context "when auto_cleanup is enabled" do
      before do
        allow(MigrationGuard.configuration).to receive_messages(auto_cleanup: true, cleanup_after_days: 30)
      end

      it "removes old rolled_back records" do
        expect { tracker.cleanup_old_records }.to change(MigrationGuard::MigrationGuardRecord, :count).by(-1)
        expect(MigrationGuard::MigrationGuardRecord.exists?(old_record.id)).to be false
      end

      it "keeps recent records" do
        tracker.cleanup_old_records
        expect(MigrationGuard::MigrationGuardRecord.exists?(recent_record.id)).to be true
      end

      it "keeps applied records regardless of age" do
        old_applied = MigrationGuard::MigrationGuardRecord.create!(
          version: "20220101000000",
          status: "applied",
          created_at: 90.days.ago
        )

        tracker.cleanup_old_records
        expect(MigrationGuard::MigrationGuardRecord.exists?(old_applied.id)).to be true
      end
    end

    context "when auto_cleanup is disabled" do
      before do
        allow(MigrationGuard.configuration).to receive(:auto_cleanup).and_return(false)
      end

      it "does not remove any records" do
        expect { tracker.cleanup_old_records }.not_to change(MigrationGuard::MigrationGuardRecord, :count)
      end
    end
  end
end
