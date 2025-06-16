# frozen_string_literal: true

require "spec_helper"
require "rake"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Rake tasks availability", type: :integration do
  # rubocop:disable RSpec/BeforeAfterAll, RSpec/InstanceVariable
  before(:all) do
    # Load rake tasks manually for testing
    @rake = Rake.application

    # Load Rails and setup minimal environment
    require "rails"
    unless Rails.respond_to?(:root)
      Rails.define_singleton_method(:root) do
        Pathname.new(File.expand_path("..", __dir__))
      end
    end
    Rails.define_singleton_method(:env) { ActiveSupport::StringInquirer.new("test") } unless Rails.respond_to?(:env)

    # Define environment task if not exists
    unless @rake.lookup("environment")
      Rake::Task.define_task(:environment) do
        # Empty task for testing
      end
    end

    # Load the migration guard rake tasks
    load File.expand_path("../lib/tasks/migration_guard.rake", __dir__)
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
