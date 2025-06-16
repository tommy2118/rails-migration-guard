# frozen_string_literal: true

require "rails_helper"
require "generators/migration_guard/hooks_generator"
require "fileutils"
require "tmpdir"

RSpec.describe MigrationGuard::Generators::HooksGenerator do
  let(:destination_root) { Dir.mktmpdir }
  let(:generator) { described_class.new([], options, destination_root: destination_root) }
  let(:options) { {} }

  before do
    FileUtils.mkdir_p(File.join(destination_root, ".git", "hooks"))
    allow(generator).to receive(:say)
    allow(generator).to receive(:create_file) do |path, content|
      File.write(File.join(destination_root, path), content)
    end
    allow(generator).to receive(:chmod) do |path, mode|
      File.chmod(mode, File.join(destination_root, path))
    end
    allow(generator).to receive(:copy_file) do |source, dest|
      FileUtils.cp(File.join(destination_root, source), File.join(destination_root, dest))
    end
    allow(generator).to receive(:empty_directory)
  end

  after do
    FileUtils.remove_entry(destination_root)
  end

  describe "git hooks installation" do
    context "when git directory exists" do
      it "creates post-checkout hook" do
        generator.invoke_all

        hook_file = File.join(destination_root, ".git", "hooks", "post-checkout")
        expect(File.exist?(hook_file)).to be true
        expect(File.executable?(hook_file)).to be true

        content = File.read(hook_file)
        expect(content).to include("#!/bin/sh")
        expect(content).to include("rails db:migration:check_branch_change[$1,$2,$3]")
      end

      it "creates pre-push hook when requested" do
        generator = described_class.new(["--pre-push"], {}, destination_root: destination_root)
        allow(generator).to receive(:say)
        allow(generator).to receive(:create_file) do |path, content|
          File.write(File.join(destination_root, path), content)
        end
        allow(generator).to receive(:chmod) do |path, mode|
          File.chmod(mode, File.join(destination_root, path))
        end
        allow(generator).to receive(:empty_directory)

        generator.invoke_all

        hook_file = File.join(destination_root, ".git", "hooks", "pre-push")
        expect(File.exist?(hook_file)).to be true
        expect(File.executable?(hook_file)).to be true

        content = File.read(hook_file)
        expect(content).to include("rails db:migration:check")
      end

      it "backs up existing hooks" do
        existing_hook = File.join(destination_root, ".git", "hooks", "post-checkout")
        File.write(existing_hook, "existing content")

        generator.invoke_all

        backup_file = "#{existing_hook}.backup"
        expect(File.exist?(backup_file)).to be true
        expect(File.read(backup_file)).to eq("existing content")
      end

      it "skips backup if content is identical" do
        hook_file = File.join(destination_root, ".git", "hooks", "post-checkout")
        temp_generator = described_class.new
        expected_content = temp_generator.send(:post_checkout_content)
        File.write(hook_file, expected_content)

        generator.invoke_all

        backup_file = "#{hook_file}.backup"
        expect(File.exist?(backup_file)).to be false
      end
    end

    context "when not in a git repository" do
      before do
        FileUtils.rm_rf(File.join(destination_root, ".git"))
      end

      it "displays error message and exits" do
        allow(generator).to receive(:say)
        allow(generator).to receive(:exit)

        generator.check_git_repository

        expect(generator).to have_received(:say).with(/Not a git repository/, :red)
        expect(generator).to have_received(:exit).with(1)
      end
    end

    context "with configuration options" do
      it "respects --skip-pre-push option" do
        generator = described_class.new(["--skip-pre-push"], {}, destination_root: destination_root)
        allow(generator).to receive(:say)
        allow(generator).to receive(:create_file) do |path, content|
          File.write(File.join(destination_root, path), content)
        end
        allow(generator).to receive(:chmod) do |path, mode|
          File.chmod(mode, File.join(destination_root, path))
        end
        allow(generator).to receive(:empty_directory)

        generator.invoke_all

        post_checkout = File.join(destination_root, ".git", "hooks", "post-checkout")
        pre_push = File.join(destination_root, ".git", "hooks", "pre-push")

        expect(File.exist?(post_checkout)).to be true
        expect(File.exist?(pre_push)).to be false
      end

      it "no longer supports custom message parameter" do
        generator = described_class.new(["--message", "Custom warning message"], {}, destination_root: destination_root)

        expect(generator.options[:message]).to eq("Custom warning message")
      end
    end
  end

  describe "hook content" do
    it "post-checkout hook runs branch change check" do
      generator.invoke_all

      hook_file = File.join(destination_root, ".git", "hooks", "post-checkout")
      content = File.read(hook_file)

      expect(content).to include("# Rails Migration Guard post-checkout hook")
      expect(content).to include('if [ "$3" = "1" ]')
      expect(content).to include("bundle exec rails db:migration:check_branch_change[$1,$2,$3]")
    end

    it "pre-push hook checks for orphaned migrations" do
      generator = described_class.new(["--pre-push"], {}, destination_root: destination_root)
      allow(generator).to receive(:say)
      allow(generator).to receive(:create_file) do |path, content|
        File.write(File.join(destination_root, path), content)
      end
      allow(generator).to receive(:chmod) do |path, mode|
        File.chmod(mode, File.join(destination_root, path))
      end
      allow(generator).to receive(:empty_directory)

      generator.invoke_all

      hook_file = File.join(destination_root, ".git", "hooks", "pre-push")
      content = File.read(hook_file)

      aggregate_failures do
        expect(content).to include("# Rails Migration Guard pre-push hook")
        expect(content).to include("bundle exec rails db:migration:check")
        expect(content).to include("if [ $? -ne 0 ]")
        expect(content).to include("exit 1")
      end
    end
  end
end
