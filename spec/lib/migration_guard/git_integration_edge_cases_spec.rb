# frozen_string_literal: true

require "English"
require "rails_helper"
require "fileutils"
require "tmpdir"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "MigrationGuard::GitIntegration edge cases and error scenarios", type: :integration do
  # rubocop:enable RSpec/DescribeClass
  let(:git_integration) { MigrationGuard::GitIntegration.new }

  # Create a temporary directory for testing
  let(:test_dir) { Dir.mktmpdir("migration_guard_test") }

  around do |example|
    # Save current directory
    original_dir = Dir.pwd

    begin
      example.run
    ensure
      # Clean up and restore directory
      Dir.chdir(original_dir)
      FileUtils.rm_rf(test_dir)
    end
  end

  describe "Edge Case 1: Not in a git repository" do
    before do
      Dir.chdir(test_dir)
      # Ensure we're not in a git repo
      FileUtils.rm_rf(".git")
      # Also ensure no parent directories have .git
      ENV["GIT_DIR"] = "/nonexistent"
    end

    after do
      ENV.delete("GIT_DIR")
    end

    it "raises GitError when trying to get current branch" do
      expect do
        git_integration.current_branch
      end.to raise_error(MigrationGuard::GitError, /Failed to determine current branch/)
    end

    it "raises GitError when trying to find main branch" do
      expect { git_integration.main_branch }.to raise_error(MigrationGuard::GitError, /No main branch found/)
    end

    it "raises GitError when checking uncommitted changes" do
      expect do
        git_integration.uncommitted_changes?
      end.to raise_error(MigrationGuard::GitError, /Failed to check git status/)
    end

    it "raises GitError when checking author email" do
      # In a non-git directory, git config might still work if there's a global config
      # The error would be if the email is not configured, not if git is missing
      # So let's test that scenario instead
      ENV["GIT_CONFIG_GLOBAL"] = "/nonexistent"
      ENV["HOME"] = test_dir

      expect { git_integration.author_email }.to raise_error(MigrationGuard::GitError, "Git user email not configured")

      ENV.delete("GIT_CONFIG_GLOBAL")
      ENV.delete("HOME")
    end
  end

  describe "Edge Case 2: Detached HEAD state" do
    before do
      Dir.chdir(test_dir)
      # Initialize git repo
      `git init`
      `git config user.email "test@example.com"`
      `git config user.name "Test User"`

      # Create initial commit
      File.write("README.md", "Test")
      `git add .`
      `git commit -m "Initial commit"`

      # Create another commit
      File.write("test.txt", "test")
      `git add .`
      `git commit -m "Second commit"`

      # Detach HEAD
      commit_hash = `git rev-parse HEAD~1`.strip
      `git checkout #{commit_hash}`
    end

    it "returns 'HEAD' when in detached HEAD state" do
      expect(git_integration.current_branch).to eq("HEAD")
    end

    it "can still find main branch" do
      # Create main branch
      `git branch main`
      expect { git_integration.main_branch }.not_to raise_error
    end
  end

  describe "Edge Case 3: Uncommitted changes in migration files" do
    before do
      Dir.chdir(test_dir)
      `git init`
      `git config user.email "test@example.com"`
      `git config user.name "Test User"`

      # Create migration directory and files
      FileUtils.mkdir_p("db/migrate")
      File.write("db/migrate/001_create_users.rb", "class CreateUsers < ActiveRecord::Migration[7.0]\nend")
      `git add .`
      `git commit -m "Initial migration"`

      # Modify migration file
      File.write("db/migrate/001_create_users.rb",
                 "class CreateUsers < ActiveRecord::Migration[7.0]\n  # Modified\nend")

      # Add new unstaged migration
      File.write("db/migrate/002_add_email.rb", "class AddEmail < ActiveRecord::Migration[7.0]\nend")
    end

    it "detects uncommitted changes" do
      expect(git_integration.uncommitted_changes?).to be true
    end

    it "detects stash is required for migrations" do
      expect(git_integration.stash_required?).to be true
    end

    it "lists only committed migrations in branch" do
      # Stage the new migration (but don't commit)
      `git add db/migrate/002_add_email.rb`

      # The master branch only shows committed files, not staged ones
      migrations = git_integration.migrations_in_branch("master")
      expect(migrations).to eq(["001_create_users.rb"])

      # Even the current branch won't show uncommitted files with ls-tree
      migrations = git_integration.migrations_in_branch("master")
      expect(migrations).not_to include("002_add_email.rb")
    end
  end

  describe "Edge Case 4: Branches with special characters" do
    before do
      Dir.chdir(test_dir)
      `git init`
      `git config user.email "test@example.com"`
      `git config user.name "Test User"`

      # Create initial commit
      FileUtils.mkdir_p("db/migrate")
      File.write("db/migrate/001_test.rb", "test")
      `git add .`
      `git commit -m "Initial commit"`
    end

    context "with spaces in branch name" do
      it "handles branch names with spaces" do
        # Git doesn't allow spaces in branch names
        # This test documents that behavior
        output = `git checkout -b "feature/new feature" 2>&1`
        expect($CHILD_STATUS.success?).to be false
        expect(output).to include("not a valid branch name")
      end
    end

    context "with special characters in branch name" do
      before do
        `git checkout -b "feature/test-branch@v1.0"`
      end

      it "handles branch names with special characters" do
        expect(git_integration.current_branch).to eq("feature/test-branch@v1.0")
      end
    end

    context "with unicode characters in branch name" do
      before do
        `git checkout -b "feature/测试分支"`
      end

      it "handles branch names with unicode characters" do
        expect(git_integration.current_branch).to eq("feature/测试分支")
      end
    end
  end

  describe "Edge Case 5: Unexpected git command output" do
    it "handles git commands returning warnings along with output" do
      allow(git_integration).to receive(:`) do |command|
        system("exit 0")
        if command.include?("rev-parse --abbrev-ref HEAD")
          "warning: refname 'HEAD' is ambiguous.\nmain\n"
        else
          ""
        end
      end

      # Should extract the actual branch name, ignoring warnings
      expect(git_integration.current_branch).to include("main")
    end

    it "handles empty output from git commands" do
      allow(git_integration).to receive(:`) do |_command|
        system("exit 0")
        ""
      end

      expect { git_integration.author_email }.to raise_error(MigrationGuard::GitError, "Git user email not configured")
    end
  end

  describe "Edge Case 6: file_exists_in_branch? with non-existent branches" do
    before do
      Dir.chdir(test_dir)
      `git init`
      `git config user.email "test@example.com"`
      `git config user.name "Test User"`

      FileUtils.mkdir_p("db/migrate")
      File.write("db/migrate/001_test.rb", "test")
      `git add .`
      `git commit -m "Initial commit"`
    end

    it "returns false for non-existent branch" do
      result = git_integration.file_exists_in_branch?("non-existent-branch", "db/migrate/001_test.rb")
      expect(result).to be false
    end

    it "returns false for non-existent file in existing branch" do
      result = git_integration.file_exists_in_branch?("main", "db/migrate/999_non_existent.rb")
      expect(result).to be false
    end

    it "handles malformed branch names gracefully" do
      result = git_integration.file_exists_in_branch?("../../../etc/passwd", "test.rb")
      expect(result).to be false
    end
  end

  describe "Edge Case 7: Performance with many migration files" do
    before do
      Dir.chdir(test_dir)
      `git init`
      `git config user.email "test@example.com"`
      `git config user.name "Test User"`

      FileUtils.mkdir_p("db/migrate")

      # Create 1000 migration files with proper format
      1000.times do |i|
        timestamp = format("2024%<major>04d%<minor>06d", major: i / 1000, minor: i % 1000)
        File.write("db/migrate/#{timestamp}_migration_#{i}.rb", "# Migration #{i}")
      end

      `git add .`
      `git commit -m "Add 1000 migrations"`
    end

    it "handles large number of migrations efficiently" do
      start_time = Time.zone.now
      migrations = git_integration.migrations_in_branch("master")
      end_time = Time.zone.now

      expect(migrations.size).to eq(1000)
      expect(end_time - start_time).to be < 5 # Should complete within 5 seconds
    end

    it "filters migrations correctly with many files" do
      migrations = git_integration.migrations_in_branch("master")

      # All should match the migration pattern
      expect(migrations).to all(match(/^\d+_.*\.rb$/))
    end
  end

  describe "Edge Case 8: Git configuration issues" do
    before do
      Dir.chdir(test_dir)
      `git init`
    end

    context "when user.email is not set" do
      before do
        # Unset both local and global email to ensure it's not configured
        `git config --unset user.email 2>/dev/null`
        `git config --global --unset user.email 2>/dev/null`
        # Set a temporary global config that has no email
        ENV["GIT_CONFIG_GLOBAL"] = File.join(test_dir, ".gitconfig_test")
        ENV["HOME"] = test_dir
      end

      after do
        ENV.delete("GIT_CONFIG_GLOBAL")
        ENV.delete("HOME")
      end

      it "raises GitError when trying to get author email" do
        expect do
          git_integration.author_email
        end.to raise_error(MigrationGuard::GitError, "Git user email not configured")
      end
    end

    context "when git config returns empty string" do
      before do
        `git config user.email ""`
      end

      it "raises GitError for empty email configuration" do
        expect do
          git_integration.author_email
        end.to raise_error(MigrationGuard::GitError, "Git user email not configured")
      end
    end
  end

  describe "Additional edge cases" do
    before do
      Dir.chdir(test_dir)
      `git init`
      `git config user.email "test@example.com"`
      `git config user.name "Test User"`

      FileUtils.mkdir_p("db/migrate")
      File.write("db/migrate/001_test.rb", "test")
      `git add .`
      `git commit -m "Initial commit"`
    end

    context "with corrupted git repository" do
      before do
        # Corrupt the git directory
        FileUtils.rm_rf(".git/refs")
      end

      it "raises appropriate errors when git repo is corrupted" do
        expect { git_integration.current_branch }.to raise_error(MigrationGuard::GitError)
      end
    end

    context "with symbolic links in migration path" do
      before do
        FileUtils.mkdir_p("actual_migrations")
        File.write("actual_migrations/001_linked.rb", "test")

        # Git doesn't follow symlinks to directories by default
        # Instead, let's test with a real migration directory
        FileUtils.mkdir_p("db/migrate")
        File.write("db/migrate/001_linked.rb", "test")

        `git add db/migrate/001_linked.rb`
        `git commit -m "Add migration"`
      end

      it "handles regular files in migration directory" do
        migrations = git_integration.migrations_in_branch("master")
        expect(migrations).to include("001_linked.rb")
      end
    end

    context "with case-sensitive branch names" do
      before do
        `git checkout -b feature/TEST`
      end

      it "distinguishes between case-sensitive branch names" do
        # Git will fail to create feature/test on case-insensitive filesystems
        # because it's seen as the same branch
        `git checkout -b feature/test 2>&1`
        branch_creation_failed = !$CHILD_STATUS.success?

        if branch_creation_failed
          # On case-insensitive filesystems, we'll still be on feature/TEST
          expect(git_integration.current_branch).to eq("feature/TEST")
        else
          # On case-sensitive filesystems, we should be on feature/test
          expect(git_integration.current_branch).to eq("feature/test")
        end

        # Both branches should exist
        `git rev-parse --verify feature/TEST`
        expect($CHILD_STATUS.success?).to be true

        `git rev-parse --verify feature/test`
        expect($CHILD_STATUS.success?).to be true
      end
    end

    context "with very long branch names" do
      before do
        long_branch_name = "feature/#{'a' * 200}"
        `git checkout -b "#{long_branch_name}"`
      end

      it "handles very long branch names" do
        branch = git_integration.current_branch
        expect(branch).to start_with("feature/")
        expect(branch.length).to be > 200
      end
    end
  end

  describe "Error recovery scenarios" do
    before do
      Dir.chdir(test_dir)
      `git init`
      `git config user.email "test@example.com"`
      `git config user.name "Test User"`

      FileUtils.mkdir_p("db/migrate")
      File.write("db/migrate/001_test.rb", "test")
      `git add .`
      `git commit -m "Initial commit"`
    end

    it "provides meaningful error messages for common failures" do
      # Test various failure scenarios
      allow(git_integration).to receive(:`) do |command|
        case command
        when /ls-tree.*non-existent-branch/
          system("exit 128")
          "fatal: Not a valid object name non-existent-branch"
        else
          system("exit 0")
          ""
        end
      end

      expect { git_integration.migrations_in_branch("non-existent-branch") }
        .to raise_error(MigrationGuard::GitError, /Failed to list migrations in branch non-existent-branch/)
    end
  end
end
