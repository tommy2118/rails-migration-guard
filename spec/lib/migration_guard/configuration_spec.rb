# frozen_string_literal: true

require "rails_helper"

RSpec.describe MigrationGuard::Configuration do
  let(:config) { described_class.new }

  describe "#enabled_environments" do
    it "defaults to development and staging" do
      expect(config.enabled_environments).to eq(%i[development staging])
    end

    it "can be customized" do
      config.enabled_environments = [:development]
      expect(config.enabled_environments).to eq([:development])
    end
  end

  describe "#git_integration_level" do
    it "defaults to :warning" do
      expect(config.git_integration_level).to eq(:warning)
    end

    it "accepts valid levels" do
      %i[off warning auto_rollback].each do |level|
        config.git_integration_level = level
        expect(config.git_integration_level).to eq(level)
      end
    end

    it "raises error for invalid levels" do
      expect { config.git_integration_level = :invalid }.to raise_error(MigrationGuard::ConfigurationError)
    end
  end

  describe "#tracking_detail" do
    it "defaults to all details enabled" do
      expect(config.track_branch).to be true
      expect(config.track_author).to be true
      expect(config.track_timestamp).to be true
    end

    it "can disable specific tracking" do
      config.track_branch = false
      config.track_author = false
      expect(config.track_branch).to be false
      expect(config.track_author).to be false
      expect(config.track_timestamp).to be true
    end
  end

  describe "#behavior_options" do
    it "has sensible defaults" do
      expect(config.sandbox_mode).to be false
      expect(config.warn_on_switch).to be true
      expect(config.block_deploy_with_orphans).to be false
    end

    it "can be customized" do
      config.sandbox_mode = true
      config.warn_on_switch = false
      config.block_deploy_with_orphans = true

      expect(config.sandbox_mode).to be true
      expect(config.warn_on_switch).to be false
      expect(config.block_deploy_with_orphans).to be true
    end
  end

  describe "#cleanup_policies" do
    it "defaults to manual cleanup" do
      expect(config.auto_cleanup).to be false
      expect(config.cleanup_after_days).to eq(30)
    end

    it "can enable auto cleanup with custom age" do
      config.auto_cleanup = true
      config.cleanup_after_days = 7

      expect(config.auto_cleanup).to be true
      expect(config.cleanup_after_days).to eq(7)
    end

    it "validates cleanup_after_days is positive" do
      expect { config.cleanup_after_days = 0 }.to raise_error(MigrationGuard::ConfigurationError)
      expect { config.cleanup_after_days = -1 }.to raise_error(MigrationGuard::ConfigurationError)
    end
  end

  describe "#main_branch_names" do
    it "defaults to common branch names" do
      expect(config.main_branch_names).to eq(%w[main master trunk])
    end

    it "can be customized" do
      config.main_branch_names = %w[develop main]
      expect(config.main_branch_names).to eq(%w[develop main])
    end
  end

  describe "#to_h" do
    it "returns all configuration as a hash" do
      hash = config.to_h

      expect(hash).to include(
        enabled_environments: %i[development staging],
        git_integration_level: :warning,
        track_branch: true,
        track_author: true,
        track_timestamp: true,
        sandbox_mode: false,
        warn_on_switch: true,
        block_deploy_with_orphans: false,
        auto_cleanup: false,
        cleanup_after_days: 30,
        main_branch_names: %w[main master trunk]
      )
    end
  end

  describe "#validate" do
    it "passes for valid configuration" do
      expect { config.validate }.not_to raise_error
    end

    it "raises error for invalid git integration level" do
      allow(config).to receive(:git_integration_level).and_return(:invalid)
      expect { config.validate }.to raise_error(MigrationGuard::ConfigurationError)
    end

    it "raises error for empty enabled_environments" do
      config.enabled_environments = []
      expect { config.validate }.to raise_error(MigrationGuard::ConfigurationError)
    end

    it "raises error for empty main_branch_names" do
      config.main_branch_names = []
      expect { config.validate }.to raise_error(MigrationGuard::ConfigurationError)
    end
  end
end
