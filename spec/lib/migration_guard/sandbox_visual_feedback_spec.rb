# frozen_string_literal: true

require "rails_helper"
require_relative "../../../lib/migration_guard/migration_extension"

# rubocop:disable RSpec/SpecFilePathFormat, RSpec/DescribeMethod
RSpec.describe MigrationGuard::MigrationExtension, "sandbox visual feedback" do
  # rubocop:enable RSpec/SpecFilePathFormat, RSpec/DescribeMethod
  let(:test_migration_class) do
    Class.new(ActiveRecord::Migration[7.0]) do
      include MigrationGuard::MigrationExtension

      def self.version
        "20240617123456"
      end

      def up
        # Empty migration for testing
      end
    end
  end

  let(:migration_instance) { test_migration_class.new }

  before do
    allow(MigrationGuard).to receive(:enabled?).and_return(true)

    # Mock the connection and transaction behavior
    connection = instance_double(ActiveRecord::ConnectionAdapters::AbstractAdapter)
    allow(migration_instance).to receive(:connection).and_return(connection)
    allow(connection).to receive(:transaction).and_yield
  end

  describe "sandbox mode helper methods" do
    context "when testing should_display_sandbox_messages?" do
      it "returns true in development environment" do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))

        expect(migration_instance.send(:should_display_sandbox_messages?)).to be true
      end

      it "returns false when MIGRATION_GUARD_SANDBOX_QUIET is set" do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
        ENV["MIGRATION_GUARD_SANDBOX_QUIET"] = "true"

        expect(migration_instance.send(:should_display_sandbox_messages?)).to be false

        ENV.delete("MIGRATION_GUARD_SANDBOX_QUIET")
      end

      it "returns false in test environment without verbose flag" do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("test"))

        expect(migration_instance.send(:should_display_sandbox_messages?)).to be false
      end

      it "returns true in test environment with verbose flag" do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("test"))
        ENV["MIGRATION_GUARD_SANDBOX_VERBOSE"] = "true"

        expect(migration_instance.send(:should_display_sandbox_messages?)).to be true

        ENV.delete("MIGRATION_GUARD_SANDBOX_VERBOSE")
      end
    end

    context "when testing display methods" do
      before do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
      end

      it "displays start message when conditions are met" do
        expect { migration_instance.send(:display_sandbox_start_message) }
          .to output(/🧪 SANDBOX MODE ACTIVE - Database changes will be rolled back/)
          .to_stdout
      end

      it "displays complete message when conditions are met" do
        expect { migration_instance.send(:display_sandbox_complete_message) }
          .to output(/⚠️  SANDBOX: Database changes rolled back. Schema.rb updated for inspection./)
          .to_stdout
      end
    end
  end
end
