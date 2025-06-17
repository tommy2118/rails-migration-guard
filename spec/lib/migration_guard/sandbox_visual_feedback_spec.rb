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
      
      # Expose private methods for testing
      def test_env_var_truthy?(env_var_name)
        env_var_truthy?(env_var_name)
      end
      
      def test_should_display_sandbox_messages?
        should_display_sandbox_messages?
      end
      
      def test_display_sandbox_start_message
        display_sandbox_start_message
      end
      
      def test_display_sandbox_complete_message
        display_sandbox_complete_message
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

  describe "sandbox mode constants" do
    it "has defined sandbox message constants" do
      expect(MigrationGuard::SandboxMessages::START).to eq("🧪 SANDBOX MODE ACTIVE - Database changes will be rolled back")
      expect(MigrationGuard::SandboxMessages::COMPLETE).to eq("⚠️  SANDBOX: Database changes rolled back. Schema.rb updated for inspection.")
    end
  end

  describe "environment variable helper methods" do
    describe "#env_var_truthy?" do
      it "returns true for various truthy values" do
        %w[true TRUE True 1 yes YES Yes].each do |value|
          ENV["TEST_VAR"] = value
          expect(migration_instance.test_env_var_truthy?("TEST_VAR")).to be true
        end
        ENV.delete("TEST_VAR")
      end

      it "returns false for falsy values" do
        %w[false FALSE False 0 no NO No anything_else].each do |value|
          ENV["TEST_VAR"] = value
          expect(migration_instance.test_env_var_truthy?("TEST_VAR")).to be false
        end
        ENV.delete("TEST_VAR")
      end

      it "returns false for nil/unset values" do
        ENV.delete("TEST_VAR")
        expect(migration_instance.test_env_var_truthy?("TEST_VAR")).to be false
      end
    end
  end

  describe "sandbox mode helper methods" do
    context "when testing should_display_sandbox_messages?" do
      it "returns true in development environment" do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))

        expect(migration_instance.test_should_display_sandbox_messages?).to be true
      end

      it "returns false when MIGRATION_GUARD_SANDBOX_QUIET is set to various truthy values" do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
        
        %w[true TRUE 1 yes YES].each do |value|
          ENV["MIGRATION_GUARD_SANDBOX_QUIET"] = value
          expect(migration_instance.test_should_display_sandbox_messages?).to be false
        end

        ENV.delete("MIGRATION_GUARD_SANDBOX_QUIET")
      end

      it "returns true when MIGRATION_GUARD_SANDBOX_QUIET is set to falsy values" do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
        ENV["MIGRATION_GUARD_SANDBOX_QUIET"] = "false"

        expect(migration_instance.test_should_display_sandbox_messages?).to be true

        ENV.delete("MIGRATION_GUARD_SANDBOX_QUIET")
      end

      it "returns false in test environment without verbose flag" do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("test"))

        expect(migration_instance.test_should_display_sandbox_messages?).to be false
      end

      it "returns true in test environment with various verbose flag values" do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("test"))
        
        %w[true TRUE 1 yes YES].each do |value|
          ENV["MIGRATION_GUARD_SANDBOX_VERBOSE"] = value
          expect(migration_instance.test_should_display_sandbox_messages?).to be true
        end

        ENV.delete("MIGRATION_GUARD_SANDBOX_VERBOSE")
      end
    end

    context "when testing display methods" do
      before do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
      end

      context "with Rails logger available" do
        let(:logger) { instance_double(Logger) }

        before do
          allow(Rails).to receive(:logger).and_return(logger)
        end

        it "uses Rails logger for start message" do
          expect(logger).to receive(:info).with(match(/🧪 SANDBOX MODE ACTIVE/))
          migration_instance.test_display_sandbox_start_message
        end

        it "uses Rails logger for complete message" do
          expect(logger).to receive(:warn).with(match(/⚠️  SANDBOX: Database changes rolled back/))
          migration_instance.test_display_sandbox_complete_message
        end
      end

      context "without Rails logger" do
        before do
          allow(Rails).to receive(:logger).and_return(nil)
        end

        it "displays start message to stdout when conditions are met" do
          expect { migration_instance.test_display_sandbox_start_message }
            .to output(/🧪 SANDBOX MODE ACTIVE - Database changes will be rolled back/)
            .to_stdout
        end

        it "displays complete message to stdout when conditions are met" do
          expect { migration_instance.test_display_sandbox_complete_message }
            .to output(/⚠️  SANDBOX: Database changes rolled back. Schema.rb updated for inspection./)
            .to_stdout
        end
      end

      context "when messages should not be displayed" do
        before do
          # Mock the private method that gets called internally
          allow(migration_instance).to receive(:should_display_sandbox_messages?).and_return(false)
        end

        it "does not display start message" do
          expect { migration_instance.test_display_sandbox_start_message }
            .not_to output.to_stdout
        end

        it "does not display complete message" do
          expect { migration_instance.test_display_sandbox_complete_message }
            .not_to output.to_stdout
        end
      end
    end
  end
end
