# frozen_string_literal: true

require "rails_helper"

RSpec.describe MigrationGuard::GitIntegration do
  let(:git_integration) { described_class.new }
  
  # Helper to mock system calls with specific exit status
  def stub_system_call(command, output, success: true)
    allow(git_integration).to receive(:`).with(command) do
      system("exit #{success ? 0 : 1}")
      output
    end
  end

  describe "#current_branch" do
    it "returns the current git branch" do
      stub_system_call("git rev-parse --abbrev-ref HEAD 2>&1", "feature/my-branch\n", success: true)
      
      expect(git_integration.current_branch).to eq("feature/my-branch")
    end

    it "raises GitError when git command fails" do
      stub_system_call("git rev-parse --abbrev-ref HEAD 2>&1", "fatal: not a git repository\n", success: false)
      
      expect { git_integration.current_branch }.to raise_error(MigrationGuard::GitError)
    end

    it "raises GitError when git is not available" do
      allow(git_integration).to receive(:`)
        .with("git rev-parse --abbrev-ref HEAD 2>&1")
        .and_raise(Errno::ENOENT)
      
      expect { git_integration.current_branch }.to raise_error(MigrationGuard::GitError, "Git command not found")
    end
  end

  describe "#main_branch" do
    context "when main exists" do
      it "returns main" do
        stub_system_call("git rev-parse --verify main >/dev/null 2>&1", "", success: true)
        
        expect(git_integration.main_branch).to eq("main")
      end
    end

    context "when main doesn't exist but master does" do
      it "returns master" do
        stub_system_call("git rev-parse --verify main >/dev/null 2>&1", "", success: false)
        stub_system_call("git rev-parse --verify master >/dev/null 2>&1", "", success: true)
        
        expect(git_integration.main_branch).to eq("master")
      end
    end

    context "with custom branch names in configuration" do
      before do
        allow(MigrationGuard.configuration).to receive(:main_branch_names)
          .and_return(%w[develop production])
      end

      it "checks custom branch names in order" do
        stub_system_call("git rev-parse --verify develop >/dev/null 2>&1", "", success: true)
        
        expect(git_integration.main_branch).to eq("develop")
      end
    end

    it "raises GitError when no main branch is found" do
      allow(MigrationGuard.configuration).to receive(:main_branch_names)
        .and_return(%w[main master])
      
      stub_system_call("git rev-parse --verify main >/dev/null 2>&1", "", success: false)
      stub_system_call("git rev-parse --verify master >/dev/null 2>&1", "", success: false)
      
      expect { git_integration.main_branch }.to raise_error(MigrationGuard::GitError)
    end
  end

  describe "#migrations_in_branch" do
    it "lists migration files in the specified branch" do
      stub_system_call(
        "git ls-tree -r main --name-only db/migrate/ 2>&1",
        "db/migrate/20240101000001_create_users.rb\ndb/migrate/20240102000002_add_email_to_users.rb\n",
        success: true
      )
      
      migrations = git_integration.migrations_in_branch("main")
      
      expect(migrations).to eq([
        "20240101000001_create_users.rb",
        "20240102000002_add_email_to_users.rb"
      ])
    end

    it "returns empty array when no migrations exist" do
      stub_system_call("git ls-tree -r feature/new --name-only db/migrate/ 2>&1", "", success: true)
      
      expect(git_integration.migrations_in_branch("feature/new")).to eq([])
    end

    it "raises GitError when command fails" do
      stub_system_call(
        "git ls-tree -r invalid-branch --name-only db/migrate/ 2>&1",
        "fatal: Not a valid object name invalid-branch\n",
        success: false
      )
      
      expect { git_integration.migrations_in_branch("invalid-branch") }
        .to raise_error(MigrationGuard::GitError)
    end
  end

  describe "#migration_versions_in_trunk" do
    before do
      allow(git_integration).to receive(:main_branch).and_return("main")
    end

    it "returns version numbers from migration files in trunk" do
      stub_system_call(
        "git ls-tree -r main --name-only db/migrate/ 2>&1",
        "db/migrate/20240101000001_create_users.rb\ndb/migrate/20240102000002_add_email_to_users.rb\n",
        success: true
      )
      
      versions = git_integration.migration_versions_in_trunk
      
      expect(versions).to eq(["20240101000001", "20240102000002"])
    end

    it "handles empty migration list" do
      stub_system_call("git ls-tree -r main --name-only db/migrate/ 2>&1", "", success: true)
      
      expect(git_integration.migration_versions_in_trunk).to eq([])
    end
  end

  describe "#author_email" do
    it "returns the git user email" do
      stub_system_call("git config user.email 2>&1", "developer@example.com\n", success: true)
      
      expect(git_integration.author_email).to eq("developer@example.com")
    end

    it "raises GitError when email is not configured" do
      stub_system_call("git config user.email 2>&1", "", success: false)
      
      expect { git_integration.author_email }.to raise_error(MigrationGuard::GitError)
    end
  end

  describe "#file_exists_in_branch?" do
    it "returns true when file exists" do
      stub_system_call("git cat-file -e main:db/migrate/20240101000001_create_users.rb 2>&1", "", success: true)
      
      expect(git_integration.file_exists_in_branch?("main", "db/migrate/20240101000001_create_users.rb"))
        .to be true
    end

    it "returns false when file doesn't exist" do
      stub_system_call("git cat-file -e main:db/migrate/nonexistent.rb 2>&1", "", success: false)
      
      expect(git_integration.file_exists_in_branch?("main", "db/migrate/nonexistent.rb"))
        .to be false
    end
  end

  describe "#uncommitted_changes?" do
    it "returns true when there are uncommitted changes" do
      stub_system_call("git status --porcelain 2>&1", " M db/migrate/20240101000001_create_users.rb\n", success: true)
      
      expect(git_integration.uncommitted_changes?).to be true
    end

    it "returns false when working directory is clean" do
      stub_system_call("git status --porcelain 2>&1", "", success: true)
      
      expect(git_integration.uncommitted_changes?).to be false
    end
  end

  describe "#stash_required?" do
    it "returns true when migrations have uncommitted changes" do
      stub_system_call("git status --porcelain db/migrate/ 2>&1", " M db/migrate/20240101000001_create_users.rb\n", success: true)
      
      expect(git_integration.stash_required?).to be true
    end

    it "returns false when no migration changes" do
      stub_system_call("git status --porcelain db/migrate/ 2>&1", "", success: true)
      
      expect(git_integration.stash_required?).to be false
    end
  end
end