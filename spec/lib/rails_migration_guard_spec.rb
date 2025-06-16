# frozen_string_literal: true

require "rails_helper"

RSpec.describe MigrationGuard do
  describe ".enabled?" do
    context "when Rails is not defined" do
      before do
        hide_const("Rails")
      end

      it "returns false" do
        expect(described_class.enabled?).to be false
      end

      it "logs that Rails is not defined" do
        expect(MigrationGuard::Logger).to receive(:debug).with("Rails not defined, MigrationGuard disabled")
        described_class.enabled?
      end
    end

    context "when Rails is defined" do
      context "when in production environment" do
        before do
          allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
        end

        it "returns false" do
          expect(described_class.enabled?).to be false
        end

        it "logs that it's disabled in production" do
          expect(MigrationGuard::Logger).to receive(:debug).with("MigrationGuard disabled in production")
          described_class.enabled?
        end
      end

      context "when in development environment" do
        before do
          allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
          described_class.configuration.enabled_environments = %i[development staging]
        end

        it "returns true" do
          expect(described_class.enabled?).to be true
        end

        it "logs the enabled check" do
          expect(MigrationGuard::Logger).to receive(:debug).with(
            "MigrationGuard enabled check",
            environment: "development",
            enabled: true
          )
          described_class.enabled?
        end
      end

      context "when in test environment not in enabled_environments" do
        before do
          allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("test"))
          described_class.configuration.enabled_environments = %i[development staging]
        end

        it "returns false" do
          expect(described_class.enabled?).to be false
        end
      end
    end
  end

  describe ".configuration" do
    it "returns a Configuration instance" do
      expect(described_class.configuration).to be_a(MigrationGuard::Configuration)
    end

    it "memoizes the configuration" do
      config1 = described_class.configuration
      config2 = described_class.configuration
      expect(config1).to eq(config2)
    end
  end

  describe ".configure" do
    it "yields the configuration" do
      expect { |b| described_class.configure(&b) }.to yield_with_args(described_class.configuration)
    end

    it "logs configuration details" do
      expect(MigrationGuard::Logger).to receive(:debug).with("Configuring MigrationGuard")
      expect(MigrationGuard::Logger).to receive(:debug).with(
        "MigrationGuard configured",
        enabled_environments: %i[development staging],
        log_level: :info
      )

      described_class.configure do |config|
        # Configuration block
      end
    end
  end

  describe ".reset_configuration!" do
    it "creates a new configuration instance" do
      old_config = described_class.configuration
      described_class.reset_configuration!
      new_config = described_class.configuration
      expect(new_config).not_to eq(old_config)
    end
  end
end
