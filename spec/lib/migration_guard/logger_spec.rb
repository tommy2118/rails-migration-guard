# frozen_string_literal: true

require "rails_helper"

RSpec.describe MigrationGuard::Logger do
  let(:test_logger) { instance_double(::Logger) }
  
  before do
    # Reset logger instance
    described_class.instance_variable_set(:@logger, nil)
    allow(MigrationGuard.configuration).to receive(:logger).and_return(test_logger)
  end

  describe ".logger" do
    context "when custom logger is configured" do
      it "uses the configured logger" do
        expect(described_class.logger).to eq(test_logger)
      end
    end

    context "when Rails.logger is available" do
      before do
        allow(MigrationGuard.configuration).to receive(:logger).and_return(nil)
        stub_const("Rails", double(logger: test_logger))
      end

      it "uses Rails.logger" do
        expect(described_class.logger).to eq(test_logger)
      end
    end

    context "when no logger is configured" do
      before do
        allow(MigrationGuard.configuration).to receive(:logger).and_return(nil)
        hide_const("Rails")
      end

      it "creates a new Logger with stdout" do
        expect(::Logger).to receive(:new).with($stdout).and_return(test_logger)
        expect(described_class.logger).to eq(test_logger)
      end
    end
  end

  describe "log methods" do
    let(:message) { "Test message" }
    let(:context) { { version: "123", branch: "main" } }

    before do
      allow(test_logger).to receive(:debug)
      allow(test_logger).to receive(:info)
      allow(test_logger).to receive(:warn)
      allow(test_logger).to receive(:error)
      allow(test_logger).to receive(:fatal)
    end

    describe ".debug" do
      context "when log level is debug" do
        before do
          allow(MigrationGuard.configuration).to receive(:log_level).and_return(:debug)
        end

        it "logs the message" do
          expect(test_logger).to receive(:debug).with(/Test message/)
          described_class.debug(message, context)
        end

        it "includes context in the message" do
          expect(test_logger).to receive(:debug).with(/version: 123, branch: main/)
          described_class.debug(message, context)
        end
      end

      context "when log level is info" do
        before do
          allow(MigrationGuard.configuration).to receive(:log_level).and_return(:info)
        end

        it "does not log the message" do
          expect(test_logger).not_to receive(:debug)
          described_class.debug(message, context)
        end
      end
    end

    describe ".info" do
      context "when log level is info or lower" do
        before do
          allow(MigrationGuard.configuration).to receive(:log_level).and_return(:info)
        end

        it "logs the message" do
          expect(test_logger).to receive(:info).with(/Test message/)
          described_class.info(message)
        end
      end

      context "when log level is warn" do
        before do
          allow(MigrationGuard.configuration).to receive(:log_level).and_return(:warn)
        end

        it "does not log the message" do
          expect(test_logger).not_to receive(:info)
          described_class.info(message)
        end
      end
    end

    describe ".warn" do
      before do
        allow(MigrationGuard.configuration).to receive(:log_level).and_return(:warn)
      end

      it "logs the message" do
        expect(test_logger).to receive(:warn).with(/Test message/)
        described_class.warn(message)
      end
    end

    describe ".error" do
      before do
        allow(MigrationGuard.configuration).to receive(:log_level).and_return(:error)
      end

      it "logs the message" do
        expect(test_logger).to receive(:error).with(/Test message/)
        described_class.error(message)
      end
    end

    describe ".fatal" do
      before do
        allow(MigrationGuard.configuration).to receive(:log_level).and_return(:fatal)
      end

      it "always logs the message" do
        expect(test_logger).to receive(:fatal).with(/Test message/)
        described_class.fatal(message)
      end
    end
  end

  describe "log level configuration" do
    it "respects MIGRATION_GUARD_DEBUG environment variable" do
      allow(ENV).to receive(:[]).with("MIGRATION_GUARD_DEBUG").and_return("true")
      config = MigrationGuard::Configuration.new
      expect(config.log_level).to eq(:debug)
    end

    it "defaults to info level when env var is not set" do
      allow(ENV).to receive(:[]).with("MIGRATION_GUARD_DEBUG").and_return(nil)
      config = MigrationGuard::Configuration.new
      expect(config.log_level).to eq(:info)
    end
  end
end