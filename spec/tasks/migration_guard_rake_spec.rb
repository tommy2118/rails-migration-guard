# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "migration_guard rake tasks" do
  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  before do
    # Clear task invocations between tests
    Rake::Task.tasks.each(&:reenable) if Rake::Task.tasks.any?
  end

  describe "db:migration:status" do
    it "is defined" do
      expect(Rake::Task["db:migration:status"]).to be_present
    end

    it "calls MigrationGuard::RakeTasks.status" do
      allow(MigrationGuard::RakeTasks).to receive(:status)

      Rake::Task["db:migration:status"].execute

      expect(MigrationGuard::RakeTasks).to have_received(:status).at_least(:once)
    end
  end

  describe "db:migration:rollback_orphaned" do
    it "is defined" do
      expect(Rake::Task["db:migration:rollback_orphaned"]).to be_present
    end

    it "calls MigrationGuard::RakeTasks.rollback_orphaned" do
      allow(MigrationGuard::RakeTasks).to receive(:rollback_orphaned)

      Rake::Task["db:migration:rollback_orphaned"].execute

      expect(MigrationGuard::RakeTasks).to have_received(:rollback_orphaned).at_least(:once)
    end
  end

  describe "db:migration:rollback_all_orphaned" do
    it "is defined" do
      expect(Rake::Task["db:migration:rollback_all_orphaned"]).to be_present
    end

    it "calls MigrationGuard::RakeTasks.rollback_all" do
      allow(MigrationGuard::RakeTasks).to receive(:rollback_all)

      Rake::Task["db:migration:rollback_all_orphaned"].execute

      expect(MigrationGuard::RakeTasks).to have_received(:rollback_all).at_least(:once)
    end
  end

  describe "db:migration:rollback_specific" do
    it "is defined" do
      expect(Rake::Task["db:migration:rollback_specific"]).to be_present
    end

    it "calls MigrationGuard::RakeTasks.rollback_specific with VERSION env var" do
      version = "20240115123456"
      allow(ENV).to receive(:fetch).with("VERSION", nil).and_return(version)
      allow(MigrationGuard::RakeTasks).to receive(:rollback_specific).with(version)

      Rake::Task["db:migration:rollback_specific"].execute

      expect(MigrationGuard::RakeTasks).to have_received(:rollback_specific).with(version).at_least(:once)
    end
  end

  describe "db:migration:cleanup" do
    it "is defined" do
      expect(Rake::Task["db:migration:cleanup"]).to be_present
    end

    it "calls MigrationGuard::RakeTasks.cleanup with force option from ENV" do
      allow(ENV).to receive(:[]).with("FORCE").and_return("true")
      allow(MigrationGuard::RakeTasks).to receive(:cleanup).with(force: true)

      Rake::Task["db:migration:cleanup"].execute

      expect(MigrationGuard::RakeTasks).to have_received(:cleanup).with(force: true).at_least(:once)
    end
  end

  describe "db:migration:doctor" do
    it "is defined" do
      expect(Rake::Task["db:migration:doctor"]).to be_present
    end

    it "calls MigrationGuard::RakeTasks.doctor" do
      allow(MigrationGuard::RakeTasks).to receive(:doctor)

      Rake::Task["db:migration:doctor"].execute

      expect(MigrationGuard::RakeTasks).to have_received(:doctor).at_least(:once)
    end
  end

  describe "db:migration:check_branch_change" do
    it "is defined" do
      expect(Rake::Task["db:migration:check_branch_change"]).to be_present
    end

    it "calls MigrationGuard::RakeTasks.check_branch_change with arguments" do
      allow(MigrationGuard::RakeTasks).to receive(:check_branch_change).with("abc123", "def456", "1")

      Rake::Task["db:migration:check_branch_change"].invoke("abc123", "def456", "1")

      expect(MigrationGuard::RakeTasks).to have_received(:check_branch_change).with("abc123", "def456",
                                                                                    "1").at_least(:once)
    end
  end
end
