# frozen_string_literal: true

require "rails_helper"

RSpec.describe MigrationGuard::Diagnostics::GitChecker do
  let(:issues) { [] }
  let(:warnings) { [] }
  let(:io) { StringIO.new }
  let(:git_integration) { instance_double(MigrationGuard::GitIntegration) }
  let(:checker) do
    described_class.new(issues: issues, warnings: warnings, output: io, git_integration: git_integration)
  end

  before do
    allow(MigrationGuard::Colorizer).to receive(:colorize_output?).and_return(false)
  end

  describe "#run_checks" do
    describe "git repository" do
      context "when git is available" do
        before do
          allow(git_integration).to receive_messages(current_branch: "feature/test", main_branch: "main")
        end

        it "reports success with current branch" do
          checker.run_checks

          expect(io.string).to include("Git repository")
          expect(io.string).to include("current: feature/test")
        end
      end

      context "when git raises GitError" do
        before do
          allow(git_integration).to receive(:current_branch).and_raise(MigrationGuard::GitError, "Git not found")
          allow(git_integration).to receive(:main_branch).and_raise(MigrationGuard::GitError, "Git not found")
        end

        it "adds issues for repository and branch detection" do
          checker.run_checks

          aggregate_failures do
            expect(issues.flatten).to include("Git repository not found or not configured")
            expect(issues.flatten).to include("Git branch detection failed")
          end
        end
      end

      context "when git raises StandardError" do
        before do
          allow(git_integration).to receive(:current_branch).and_raise(StandardError, "Unknown error")
          allow(git_integration).to receive(:main_branch).and_raise(StandardError, "Unknown error")
        end

        it "adds an issue for git integration failure" do
          checker.run_checks

          expect(issues.flatten).to include("Git integration failed")
        end
      end
    end

    describe "git branch detection" do
      before do
        allow(git_integration).to receive(:current_branch).and_return("main")
      end

      context "when branch detection succeeds" do
        before { allow(git_integration).to receive(:main_branch).and_return("main") }

        it "reports success with main branch" do
          checker.run_checks

          expect(io.string).to include("Git branch detection")
          expect(io.string).to include("main: main")
        end
      end
    end

    describe "target branch configuration" do
      before do
        allow(git_integration).to receive_messages(current_branch: "main", main_branch: "main")
      end

      context "when target branches are configured" do
        before do
          allow(MigrationGuard.configuration).to receive(:target_branches).and_return(%w[main develop])
        end

        it "reports configured branches" do
          checker.run_checks

          expect(io.string).to include("configured: main, develop")
        end
      end

      context "when no target branches are configured" do
        before do
          allow(MigrationGuard.configuration).to receive(:target_branches).and_return(nil)
        end

        it "adds a warning" do
          checker.run_checks

          aggregate_failures do
            expect(io.string).to include("using default")
            expect(warnings.flatten).to include("No target branches configured")
          end
        end
      end
    end
  end
end
