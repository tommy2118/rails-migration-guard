# frozen_string_literal: true

require "rails_helper"

# rubocop:disable RSpec/SpecFilePathFormat, RSpec/DescribeMethod
RSpec.describe MigrationGuard::Reporter, "sandbox mode indicator" do
  # rubocop:enable RSpec/SpecFilePathFormat, RSpec/DescribeMethod
  let(:reporter) { described_class.new }
  let(:git_integration) { instance_double(MigrationGuard::GitIntegration) }

  before do
    allow(MigrationGuard::GitIntegration).to receive(:new).and_return(git_integration)
    allow(git_integration).to receive_messages(
      current_branch: "feature/test",
      main_branch: "main",
      migration_versions_in_trunk: [],
      migration_versions_in_branches: {}
    )

    # Disable colorization for testing
    allow(MigrationGuard::Colorizer).to receive(:colorize_output?).and_return(false)
  end

  describe "#format_status_output" do
    context "when sandbox mode is enabled" do
      before do
        allow(MigrationGuard.configuration).to receive(:sandbox_mode).and_return(true)
      end

      it "includes sandbox mode indicator in the status output" do
        output = reporter.format_status_output

        aggregate_failures do
          expect(output).to include("Migration Status (main branch)")
          expect(output).to include(MigrationGuard::SandboxMessages::START)
          expect(output).to include("═" * 55)
        end
      end
    end

    context "when sandbox mode is disabled" do
      before do
        allow(MigrationGuard.configuration).to receive(:sandbox_mode).and_return(false)
      end

      it "does not include sandbox mode indicator" do
        output = reporter.format_status_output

        aggregate_failures do
          expect(output).to include("Migration Status (main branch)")
          expect(output).not_to include("SANDBOX MODE")
          expect(output).to include("═" * 55)
        end
      end
    end

    context "with target branches configured and sandbox mode enabled" do
      before do
        allow(MigrationGuard.configuration).to receive_messages(
          sandbox_mode: true,
          target_branches: %w[main develop]
        )
        allow(git_integration).to receive(:target_branches).and_return(%w[main develop])
      end

      it "includes sandbox mode indicator with multi-branch status" do
        output = reporter.format_status_output

        aggregate_failures do
          expect(output).to include("Migration Status (branches: main, develop)")
          expect(output).to include(MigrationGuard::SandboxMessages::START)
          expect(output).to include("═" * 55)
        end
      end
    end
  end
end
