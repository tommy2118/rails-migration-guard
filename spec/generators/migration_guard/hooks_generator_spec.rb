# frozen_string_literal: true

require "rails_helper"
require "generators/migration_guard/hooks/hooks_generator"
require "fileutils"
require "tmpdir"

RSpec.describe MigrationGuard::Generators::HooksGenerator do
  let(:destination_root) { Dir.mktmpdir }
  let(:generator) { described_class.new([], {}, destination_root: destination_root) }

  before do
    FileUtils.mkdir_p(File.join(destination_root, ".git", "hooks"))
  end

  after do
    FileUtils.remove_entry(destination_root)
  end

  describe "#check_git_repository" do
    around do |example|
      Dir.chdir(destination_root) do
        example.run
      end
    end

    context "when .git directory exists" do
      it "does not raise an error" do
        expect { generator.check_git_repository }.not_to raise_error
      end
    end

    context "when not in a git repository" do
      before do
        FileUtils.rm_rf(File.join(destination_root, ".git"))
      end

      it "raises Thor::Error with appropriate message" do
        expect { generator.check_git_repository }.to raise_error(Thor::Error, "Not in a git repository")
      end
    end
  end

  describe "#post_checkout_content" do
    it "generates correct post-checkout hook content" do
      content = generator.send(:post_checkout_content)

      aggregate_failures do
        expect(content).to include("#!/bin/sh")
        expect(content).to include("# Rails Migration Guard post-checkout hook")
        expect(content).to include('if [ "$3" = "1" ]; then')
        expect(content).to include("🔍 Migration Guard: Checking for migration changes...")
        expect(content).to include("bundle exec rails db:migration:check_branch_change[$1,$2,$3]")
        expect(content).to include("docker ps")
        expect(content).to include("docker exec")
        expect(content).not_to include("2>/dev/null || true")
      end
    end
  end

  describe "#pre_push_content" do
    it "generates correct pre-push hook content" do
      content = generator.send(:pre_push_content)

      aggregate_failures do
        expect(content).to include("#!/bin/sh")
        expect(content).to include("# Rails Migration Guard pre-push hook")
        expect(content).to include("🔍 Migration Guard: Checking for orphaned migrations before push...")
        expect(content).to include("bundle exec rails db:migration:ci STRICTNESS=strict")
        expect(content).to include("if [ $exit_code -ne 0 ]; then")
        expect(content).to include("❌ Push blocked: Migration issues detected!")
        expect(content).to include("exit 1")
        expect(content).to include("docker ps")
        expect(content).to include("docker exec")
      end
    end
  end

  describe "class options" do
    it "defines pre_push option" do
      expect(described_class.class_options[:pre_push]).to be_present
      expect(described_class.class_options[:pre_push].type).to eq(:boolean)
      expect(described_class.class_options[:pre_push].default).to be false
    end

    it "defines skip_pre_push option" do
      expect(described_class.class_options[:skip_pre_push]).to be_present
      expect(described_class.class_options[:skip_pre_push].type).to eq(:boolean)
      expect(described_class.class_options[:skip_pre_push].default).to be false
    end
  end

  describe "options handling" do
    context "with --pre-push option" do
      let(:generator) { described_class.new([], { pre_push: true }, destination_root: destination_root) }

      it "sets pre_push option to true" do
        expect(generator.options[:pre_push]).to be true
      end
    end

    context "with --skip-pre-push option" do
      let(:generator) { described_class.new([], { skip_pre_push: true }, destination_root: destination_root) }

      it "sets skip_pre_push option to true" do
        expect(generator.options[:skip_pre_push]).to be true
      end
    end
  end

  describe "inheritance" do
    it "inherits from Rails::Generators::Base" do
      expect(described_class.superclass).to eq(Rails::Generators::Base)
    end
  end

  describe "#display_completion_message" do
    it "displays helpful information about the hooks" do
      expect(generator).to receive(:say).with("\nGit hooks installed successfully!", :green)
      expect(generator).to receive(:say).with("\nInstalled hooks:")
      expect(generator).to receive(:say).with("  - post-checkout: Runs migration status check when switching branches")
      expect(generator).to receive(:say).with("                   Shows warnings about orphaned migrations")
      expect(generator).to receive(:say).with("                   Supports Docker environments automatically")
      expect(generator).to receive(:say).with("\nThe hooks respect your git_integration_level configuration:")
      expect(generator).to receive(:say).with("  - :off     - Hooks installed but produce no output")
      expect(generator).to receive(:say).with("  - :warning - Shows warnings but doesn't block operations (default)")
      expect(generator).to receive(:say)
        .with("  - :auto_rollback - Same as warning (auto-rollback not implemented in hooks)")
      expect(generator).to receive(:say).with("\nTo uninstall, simply delete the hook files from .git/hooks/")
      expect(generator).to receive(:say).with("To test: switch branches or try to push with orphaned migrations")

      generator.display_completion_message
    end
  end
end
