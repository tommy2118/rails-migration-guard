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
    reporter = MigrationGuard::Reporter.new
    expect { reporter.status_report }.not_to raise_error
  end

  context "when running with Ruby 3.4+" do
    it "has access to extracted stdlib gems" do
      skip "Not running on Ruby 3.4+" unless RUBY_VERSION >= "3.4.0"

      expect(defined?(Logger)).to be_truthy
      expect(defined?(Mutex_m)).to be_truthy
    end
  end
end
# rubocop:enable RSpec/DescribeClass
