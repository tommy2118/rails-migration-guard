# frozen_string_literal: true

require "rails_helper"
require "generators/migration_guard/hooks/hooks_generator"

RSpec.describe MigrationGuard::Generators::HooksGenerator do
  let(:destination_root) { File.expand_path("../../tmp", __dir__) }
  let(:generator) { described_class.new }

  before do
    FileUtils.rm_rf(destination_root)
    FileUtils.mkdir_p(destination_root)
    FileUtils.mkdir_p(File.join(destination_root, ".git"))

    allow(generator).to receive(:destination_root).and_return(destination_root)
  end

  after do
    FileUtils.rm_rf(destination_root)
  end

  describe "git hooks installation" do
    context "when git directory exists" do
      it "creates post-checkout hook" do
        generator.check_git_repository
        generator.install_post_checkout_hook
        generator.display_completion_message

        hook_file = File.join(destination_root, ".git/hooks/post-checkout")
        expect(File).to exist(hook_file)
        expect(File.read(hook_file)).to include("Rails Migration Guard post-checkout hook")
        expect(File.read(hook_file)).to include("bundle exec rails db:migration:check_branch_change")
        expect(File.executable?(hook_file)).to be true
      end

      it "creates pre-push hook when requested" do
        run_generator %w[--pre-push]

        hook_file = File.join(destination_root, ".git/hooks/pre-push")
        expect(File).to exist(hook_file)
        expect(File.read(hook_file)).to include("Rails Migration Guard pre-push hook")
        expect(File.read(hook_file)).to include("bundle exec rails db:migration:check")
        expect(File.executable?(hook_file)).to be true
      end

      it "skips pre-push hook by default" do
        run_generator

        hook_file = File.join(destination_root, ".git/hooks/pre-push")
        expect(File).not_to exist(hook_file)
      end

      it "backs up existing hooks" do
        existing_content = "#!/bin/sh\n# Existing hook"
        hook_path = File.join(destination_root, ".git/hooks/post-checkout")
        FileUtils.mkdir_p(File.dirname(hook_path))
        File.write(hook_path, existing_content)

        run_generator

        backup_file = "#{hook_path}.backup"
        expect(File).to exist(backup_file)
        expect(File.read(backup_file)).to eq(existing_content)
      end

      it "skips backup if content is identical" do
        run_generator # First run

        hook_path = File.join(destination_root, ".git/hooks/post-checkout")
        original_content = File.read(hook_path)

        run_generator # Second run

        backup_file = "#{hook_path}.backup"
        expect(File).not_to exist(backup_file)
        expect(File.read(hook_path)).to eq(original_content)
      end
    end

    context "when not in a git repository" do
      before do
        FileUtils.rm_rf(File.join(destination_root, ".git"))
      end

      it "displays error message and exits" do
        expect { run_generator }.to raise_error(SystemExit)
      end
    end

    context "with configuration options" do
      it "respects --skip-pre-push option" do
        run_generator %w[--pre-push --skip-pre-push]

        hook_file = File.join(destination_root, ".git/hooks/pre-push")
        expect(File).not_to exist(hook_file)
      end

      it "no longer supports custom message parameter" do
        run_generator %w[--message Custom]

        # Should still work, just ignoring the invalid option
        hook_file = File.join(destination_root, ".git/hooks/post-checkout")
        expect(File).to exist(hook_file)
      end
    end
  end

  describe "hook content" do
    it "post-checkout hook runs branch change check" do
      run_generator

      hook_content = File.read(File.join(destination_root, ".git/hooks/post-checkout"))

      aggregate_failures do
        expect(hook_content).to include('if [ "$3" = "1" ]')
        expect(hook_content).to include("bundle exec rails db:migration:check_branch_change[$1,$2,$3]")
        expect(hook_content).to include("2>/dev/null || true")
      end
    end

    it "pre-push hook checks for orphaned migrations" do
      run_generator %w[--pre-push]

      hook_content = File.read(File.join(destination_root, ".git/hooks/pre-push"))

      aggregate_failures do
        expect(hook_content).to include("Checking for orphaned migrations before push")
        expect(hook_content).to include("bundle exec rails db:migration:check")
        expect(hook_content).to include("Push cancelled: Orphaned migrations detected!")
        expect(hook_content).to include("rails db:migration:rollback_orphaned")
      end
    end
  end
end
