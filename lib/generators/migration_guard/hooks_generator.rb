# frozen_string_literal: true

require "fileutils"
require "optparse"

module MigrationGuard
  module Generators
    class HooksGenerator
      attr_reader :options, :destination_root

      def initialize(args = [], _options = {}, config = {})
        @args = args
        @options = parse_options(args)
        @destination_root = config[:destination_root] || Dir.pwd
      end

      def self.desc
        "Installs git hooks for Rails Migration Guard"
      end

      def invoke_all
        check_git_repository
        create_hooks_directory
        install_post_checkout_hook
        install_pre_push_hook
        display_completion_message
      end

      def check_git_repository
        git_dir = File.join(@destination_root, ".git")
        return if File.directory?(git_dir)

        say "Not a git repository. Please run this generator from the root of your git repository.", :red
        exit 1 # rubocop:disable Rails/Exit
      end

      def create_hooks_directory
        hooks_dir = File.join(@destination_root, ".git", "hooks")
        FileUtils.mkdir_p(hooks_dir) unless File.directory?(hooks_dir)
      end

      def install_post_checkout_hook
        create_git_hook("post-checkout", post_checkout_content)
      end

      def install_pre_push_hook
        return if @options[:skip_pre_push]
        return unless @options[:pre_push]

        create_git_hook("pre-push", pre_push_content)
      end

      def display_completion_message
        say "\nGit hooks installed successfully!", :green
        say "\nInstalled hooks:"
        say "  - post-checkout: Runs migration status check when switching branches"
        say "  - pre-push: Checks for orphaned migrations before pushing" if @options[:pre_push]
        say "\nTo uninstall, simply delete the hook files from .git/hooks/"
      end

      private

      def parse_options(args)
        options = {}
        parser = OptionParser.new do |opts|
          opts.on("--pre-push", "Install pre-push hook") do
            options[:pre_push] = true
          end

          opts.on("--skip-pre-push", "Skip pre-push hook") do
            options[:skip_pre_push] = true
          end

          opts.on("--message MSG", "Custom message to display") do |msg|
            options[:message] = msg
          end
        end

        parser.parse!(args)
        options
      end

      def say(message, _color = nil)
        # In a Rails context, this would use Rails.logger
        # For standalone usage, we use puts
        puts message # rubocop:disable Rails/Output
      end

      def create_file(path, content)
        full_path = File.join(@destination_root, path)
        File.write(full_path, content)
      end

      def chmod(path, mode)
        full_path = File.join(@destination_root, path)
        File.chmod(mode, full_path)
      end

      def copy_file(source, dest)
        source_path = File.join(@destination_root, source)
        dest_path = File.join(@destination_root, dest)
        FileUtils.cp(source_path, dest_path)
      end

      def empty_directory(path)
        full_path = File.join(@destination_root, path)
        FileUtils.mkdir_p(full_path)
      end

      def create_git_hook(name, content)
        hook_path = File.join(".git", "hooks", name)
        full_hook_path = File.join(@destination_root, hook_path)

        handle_existing_hook(name, hook_path, full_hook_path, content)

        create_file hook_path, content
        chmod hook_path, 0o755
        say "Created #{name} hook", :green
      end

      def handle_existing_hook(name, hook_path, full_hook_path, content)
        return unless File.exist?(full_hook_path)

        existing_content = File.read(full_hook_path)
        if existing_content == content
          say "#{name} hook already up to date", :yellow
          return
        end

        backup_path = "#{hook_path}.backup"
        copy_file hook_path, backup_path
        say "Backed up existing #{name} hook to #{backup_path}", :yellow
      end

      def post_checkout_content
        <<~HOOK
          #!/bin/sh
          # Rails Migration Guard post-checkout hook
          # Automatically checks migration status when switching branches

          # Arguments: $1 = previous HEAD, $2 = new HEAD, $3 = flag (1 if branch checkout)

          # Only run on branch checkout (not file checkout)
          if [ "$3" = "1" ]; then
            # Run the branch change check with the git hook parameters
            bundle exec rails db:migration:check_branch_change[$1,$2,$3] 2>/dev/null || true
          fi
        HOOK
      end

      def pre_push_content
        <<~HOOK
          #!/bin/sh
          # Rails Migration Guard pre-push hook
          # Prevents pushing when orphaned migrations are detected

          echo "Checking for orphaned migrations before push..."

          # Run migration check
          bundle exec rails db:migration:check

          # Check exit code
          if [ $? -ne 0 ]; then
            echo ""
            echo "❌ Push cancelled: Orphaned migrations detected!"
            echo ""
            echo "Please either:"
            echo "  1. Commit your migrations to include them in this push"
            echo "  2. Roll them back with 'rails db:migration:rollback_orphaned'"
            echo ""
            echo "For more details, run: rails db:migration:status"
            exit 1
          fi

          echo "✅ No orphaned migrations found. Proceeding with push..."
        HOOK
      end
    end
  end
end
