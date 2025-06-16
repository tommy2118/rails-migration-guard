# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "migration_guard rake tasks" do
  before(:all) do
    Rails.application.load_tasks
  end

  before do
    # Reenable all tasks before each test to allow multiple invocations
    Rake::Task.tasks.each(&:reenable)
  end

  describe "db:migration:status" do
    it "is defined" do
      expect(Rake::Task["db:migration:status"]).to be_present
    end

    it "calls MigrationGuard::RakeTasks.status" do
      expect(MigrationGuard::RakeTasks).to receive(:status)
      
      Rake::Task["db:migration:status"].execute
    end
  end

  describe "db:migration:rollback_orphaned" do
    it "is defined" do
      expect(Rake::Task["db:migration:rollback_orphaned"]).to be_present
    end

    it "calls MigrationGuard::RakeTasks.rollback_orphaned" do
      expect(MigrationGuard::RakeTasks).to receive(:rollback_orphaned)
      
      Rake::Task["db:migration:rollback_orphaned"].execute
    end
  end

  describe "db:migration:rollback_all_orphaned" do
    it "is defined" do
      expect(Rake::Task["db:migration:rollback_all_orphaned"]).to be_present
    end

    it "calls MigrationGuard::RakeTasks.rollback_all" do
      expect(MigrationGuard::RakeTasks).to receive(:rollback_all)
      
      Rake::Task["db:migration:rollback_all_orphaned"].execute
    end
  end

  describe "db:migration:rollback_specific" do
    it "is defined" do
      expect(Rake::Task["db:migration:rollback_specific"]).to be_present
    end

    it "calls MigrationGuard::RakeTasks.rollback_specific with VERSION env var" do
      version = "20240115123456"
      allow(ENV).to receive(:fetch).with("VERSION", nil).and_return(version)
      
      expect(MigrationGuard::RakeTasks).to receive(:rollback_specific).with(version)
      
      Rake::Task["db:migration:rollback_specific"].execute
    end
  end

  describe "db:migration:cleanup" do
    it "is defined" do
      expect(Rake::Task["db:migration:cleanup"]).to be_present
    end

    it "calls MigrationGuard::RakeTasks.cleanup with force option from ENV" do
      allow(ENV).to receive(:[]).with("FORCE").and_return("true")
      
      expect(MigrationGuard::RakeTasks).to receive(:cleanup).with(force: true)
      
      Rake::Task["db:migration:cleanup"].execute
    end
  end

  describe "db:migration:doctor" do
    it "is defined" do
      expect(Rake::Task["db:migration:doctor"]).to be_present
    end

    it "calls MigrationGuard::RakeTasks.doctor" do
      expect(MigrationGuard::RakeTasks).to receive(:doctor)
      
      Rake::Task["db:migration:doctor"].execute
    end
  end
end