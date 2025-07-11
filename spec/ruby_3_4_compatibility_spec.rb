# frozen_string_literal: true

require "rails_helper"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Ruby 3.4.1 compatibility", type: :integration do
  it "loads the gem without errors" do
    expect { require "rails_migration_guard" }.not_to raise_error
  end

  it "can track migrations without errors" do
    tracker = MigrationGuard::Tracker.new
    expect { tracker.track_migration("20240115123456", :up) }.not_to raise_error
  end

  it "can report status without errors" do
    # Mock the git integration to avoid git-related errors in test
    git_integration = instance_double(MigrationGuard::GitIntegration)
    allow(MigrationGuard::GitIntegration).to receive(:new).and_return(git_integration)
    allow(git_integration).to receive_messages(main_branch: "master", target_branches: ["master"],
                                               migration_versions_in_branches: { "master" => [] },
                                               current_branch: "master",
                                               migration_versions_in_trunk: [])

    reporter = MigrationGuard::Reporter.new
    expect { reporter.status_report }.not_to raise_error
  end

  context "when running with Ruby 3.4+" do
    it "has access to extracted stdlib gems" do
      skip "Not running on Ruby 3.4+" unless RUBY_VERSION >= "3.4.0"

      expect(defined?(Logger)).to be_truthy
      expect { require "mutex_m" }.not_to raise_error
    end
  end
end
# rubocop:enable RSpec/DescribeClass
