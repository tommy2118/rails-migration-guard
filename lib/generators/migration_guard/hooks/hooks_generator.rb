# frozen_string_literal: true

require "rails/generators"

module MigrationGuard
  module Generators
    class HooksGenerator < Rails::Generators::Base
      desc "Installs git hooks for Rails Migration Guard"

      class_option :pre_push, type: :boolean, default: false,
                              desc: "Install pre-push hook"
      class_option :skip_pre_push, type: :boolean, default: false,
                                   desc: "Skip pre-push hook installation"

      def check_git_repository
        return if File.directory?(".git")

        say_status :error, "Not a git repository. Please run this generator from the root of your git repository.", :red
        raise Thor::Error, "Not in a git repository"
      end

      def install_post_checkout_hook
        create_git_hook("post-checkout", post_checkout_content)
      end

      def install_pre_push_hook
        return if options[:skip_pre_push]
        return unless options[:pre_push]

        create_git_hook("pre-push", pre_push_content)
      end

      def display_completion_message # rubocop:disable Metrics/MethodLength
        say "\nGit hooks installed successfully!", :green
        say "\nInstalled hooks:"
        say "  - post-checkout: Runs migration status check when switching branches"
        say "                   Shows warnings about orphaned migrations"
        say "                   Supports Docker environments automatically"

        if options[:pre_push]
          say "  - pre-push: Prevents pushing with orphaned or missing migrations"
          say "              Runs in strict mode to block problematic pushes"
          say "              Supports Docker environments automatically"
        end

        say "\nThe hooks respect your git_integration_level configuration:"
        say "  - :off     - Hooks installed but produce no output"
        say "  - :warning - Shows warnings but doesn't block operations (default)"
        say "  - :auto_rollback - Same as warning (auto-rollback not implemented in hooks)"

        say "\nTo uninstall, simply delete the hook files from .git/hooks/"
        say "To test: switch branches or try to push with orphaned migrations"
      end

      private

      def create_git_hook(name, content)
        hook_path = File.join(".git", "hooks", name)

        if File.exist?(hook_path)
          existing_content = File.read(hook_path)
          if existing_content == content
            say "#{name} hook already up to date", :yellow
            return
          end

          backup_path = "#{hook_path}.backup"
          copy_file hook_path, backup_path
          say "Backed up existing #{name} hook to #{backup_path}", :yellow
        end

        create_file hook_path, content
        chmod hook_path, 0o755
        say "Created #{name} hook", :green
      end

      def post_checkout_content
        <<~HOOK
          #!/bin/sh
          # Rails Migration Guard post-checkout hook
          # Automatically checks migration status when switching branches

          # Arguments: $1 = previous HEAD, $2 = new HEAD, $3 = flag (1 if branch checkout)

          # Only run on branch checkout (not file checkout)
          if [ "$3" = "1" ]; then
            echo "🔍 Migration Guard: Checking for migration changes..."
          #{'  '}
            # Check if we're in a Docker environment
            if [ -f "docker-compose.yml" ] && docker ps 2>/dev/null | grep -q "_web_\\|_app_\\|rails"; then
              # Find the Rails container (common naming patterns)
              container=$(docker ps --format "{{.Names}}" | grep -E "_web_|_app_|rails" | head -1)
              if [ -n "$container" ]; then
                echo "Using Docker environment (container: $container)..."
                docker exec "$container" rails db:migration:check_branch_change[$1,$2,$3] || true
              else
                echo "Docker detected but no Rails container found. Running locally..."
                bundle exec rails db:migration:check_branch_change[$1,$2,$3] || true
              fi
            else
              # Run locally
              bundle exec rails db:migration:check_branch_change[$1,$2,$3] || true
            fi
          fi
        HOOK
      end

      def pre_push_content
        <<~HOOK
          #!/bin/sh
          # Rails Migration Guard pre-push hook
          # Prevents pushing when orphaned migrations are detected

          echo "🔍 Migration Guard: Checking for orphaned migrations before push..."

          # Check if we're in a Docker environment
          if [ -f "docker-compose.yml" ] && docker ps 2>/dev/null | grep -q "_web_\\|_app_\\|rails"; then
            # Find the Rails container (common naming patterns)
            container=$(docker ps --format "{{.Names}}" | grep -E "_web_|_app_|rails" | head -1)
            if [ -n "$container" ]; then
              echo "Using Docker environment (container: $container)..."
              docker exec "$container" rails db:migration:ci STRICTNESS=strict
              exit_code=$?
            else
              echo "Docker detected but no Rails container found. Running locally..."
              bundle exec rails db:migration:ci STRICTNESS=strict
              exit_code=$?
            fi
          else
            # Run locally
            bundle exec rails db:migration:ci STRICTNESS=strict
            exit_code=$?
          fi

          # Check exit code
          if [ $exit_code -ne 0 ]; then
            echo ""
            echo "❌ Push blocked: Migration issues detected!"
            echo ""
            echo "Please either:"
            echo "  1. Commit your migrations to include them in this push"
            echo "  2. Roll them back with 'rails db:migration:rollback_orphaned'"
            echo "  3. Pull latest changes if missing migrations from main branch"
            echo ""
            echo "For more details, run: rails db:migration:status"
            exit 1
          fi

          echo "✅ No migration issues found. Proceeding with push..."
        HOOK
      end
    end
  end
end
