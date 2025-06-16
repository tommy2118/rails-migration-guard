# frozen_string_literal: true

require "spec_helper"
require "rake"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Rake tasks availability", type: :integration do
  # rubocop:disable RSpec/BeforeAfterAll, RSpec/InstanceVariable
  before(:all) do
    # Enable rake task loading for this test
    ENV["TEST_RAKE_TASKS"] = "true"

    # Use the global Rake instance that has tasks loaded
    @rake = Rake.application
    @rake.load_rakefile if @rake.tasks.empty?
  end

  after(:all) do
    ENV.delete("TEST_RAKE_TASKS")
  end

  let(:rake) { @rake }
  # rubocop:enable RSpec/BeforeAfterAll, RSpec/InstanceVariable

  describe "migration guard rake tasks" do
    it "loads db:migration:status task" do
      expect(rake.tasks.map(&:name)).to include("db:migration:status")
    end

    it "loads db:migration:doctor task" do
      expect(rake.tasks.map(&:name)).to include("db:migration:doctor")
    end

    it "loads db:migration:rollback_orphaned task" do
      expect(rake.tasks.map(&:name)).to include("db:migration:rollback_orphaned")
    end

    it "loads db:migration:rollback_all_orphaned task" do
      expect(rake.tasks.map(&:name)).to include("db:migration:rollback_all_orphaned")
    end

    it "loads db:migration:rollback_specific task" do
      expect(rake.tasks.map(&:name)).to include("db:migration:rollback_specific")
    end

    it "loads db:migration:cleanup task" do
      expect(rake.tasks.map(&:name)).to include("db:migration:cleanup")
    end

    it "loads db:migration:check_branch_change task" do
      expect(rake.tasks.map(&:name)).to include("db:migration:check_branch_change")
    end
  end

  describe "task existence" do
    it "all tasks are properly defined" do
      status_task = rake.tasks.find { |t| t.name == "db:migration:status" }
      expect(status_task).not_to be_nil

      doctor_task = rake.tasks.find { |t| t.name == "db:migration:doctor" }
      expect(doctor_task).not_to be_nil
    end
  end
end
# rubocop:enable RSpec/DescribeClass
