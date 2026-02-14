# frozen_string_literal: true

require "rails_helper"

RSpec.describe MigrationGuard::CiPresenter do
  subject(:presenter) { described_class.new }

  before do
    allow(MigrationGuard::Colorizer).to receive(:colorize_output?).and_return(false)
  end

  let(:branch_info) { { current: "feature/foo", main: "main", ahead_count: 1, behind_count: 0 } }

  let(:success_result) do
    {
      status: "success",
      orphaned_migrations: [],
      missing_migrations: [],
      summary: { total_orphaned: 0, total_missing: 0, issues_found: 0,
                 main_branch: "main", current_branch: "feature/foo" },
      branch_info: branch_info,
      timestamp: "2024-06-15T10:30:00Z"
    }
  end

  let(:warning_result) do
    {
      status: "warning",
      orphaned_migrations: [
        { version: "20240101000001", branch: "feature/old", author: "dev@example.com" }
      ],
      missing_migrations: [],
      summary: { total_orphaned: 1, total_missing: 0, issues_found: 1,
                 main_branch: "main", current_branch: "feature/foo" },
      branch_info: branch_info,
      timestamp: "2024-06-15T10:30:00Z"
    }
  end

  let(:missing_result) do
    {
      status: "warning",
      orphaned_migrations: [],
      missing_migrations: [
        { version: "20240201000001" }
      ],
      summary: { total_orphaned: 0, total_missing: 1, issues_found: 1,
                 main_branch: "main", current_branch: "feature/foo" },
      branch_info: { current: "feature/foo", main: "main", ahead_count: 0, behind_count: 1 },
      timestamp: "2024-06-15T10:30:00Z"
    }
  end

  describe "#output_result" do
    context "with text format and success" do
      it "prints no-issues message" do
        expect { presenter.output_result(success_result, "text", "warning") }
          .to output(/No migration issues found/).to_stdout
      end
    end

    context "with text format and orphaned warnings" do
      it "prints orphaned details and recommended actions" do
        output = capture_stdout { presenter.output_result(warning_result, "text", "warning") }

        aggregate_failures do
          expect(output).to include("Orphaned Migrations Found")
          expect(output).to include("20240101000001")
          expect(output).to include("Recommended Actions")
        end
      end
    end

    context "with text format and missing migrations" do
      it "prints missing details and git pull recommendation" do
        output = capture_stdout { presenter.output_result(missing_result, "text", "warning") }

        aggregate_failures do
          expect(output).to include("Missing Migrations")
          expect(output).to include("20240201000001")
          expect(output).to include("git pull origin main")
        end
      end
    end

    context "with json format and success" do
      it "outputs valid JSON with success status" do
        json = capture_stdout { presenter.output_result(success_result, "json", "warning") }
        parsed = JSON.parse(json)

        aggregate_failures do
          expect(parsed["migration_guard"]["status"]).to eq("success")
          expect(parsed["migration_guard"]["exit_code"]).to eq(MigrationGuard::CiRunner::EXIT_SUCCESS)
        end
      end
    end

    context "with json format and issues" do
      it "outputs JSON with orphaned arrays and summary" do
        json = capture_stdout { presenter.output_result(warning_result, "json", "warning") }
        parsed = JSON.parse(json)

        aggregate_failures do
          expect(parsed["migration_guard"]["orphaned_migrations"].size).to eq(1)
          expect(parsed["migration_guard"]["summary"]["total_orphaned"]).to eq(1)
        end
      end
    end

    context "with json format and strict mode" do
      it "returns error exit code for warnings in strict mode" do
        json = capture_stdout { presenter.output_result(warning_result, "json", "strict") }
        parsed = JSON.parse(json)

        expect(parsed["migration_guard"]["exit_code"]).to eq(MigrationGuard::CiRunner::EXIT_ERROR)
      end
    end
  end

  describe "#output_disabled_message" do
    context "with text format" do
      it "prints not-enabled message with environment" do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))

        expect { presenter.output_disabled_message("text") }
          .to output(/not enabled in production/).to_stdout
      end
    end

    context "with json format" do
      it "outputs valid JSON with disabled status" do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))

        json = capture_stdout { presenter.output_disabled_message("json") }
        parsed = JSON.parse(json)

        expect(parsed["migration_guard"]["status"]).to eq("disabled")
      end
    end
  end

  describe "#output_error" do
    let(:error) { StandardError.new("something broke") }

    context "with text format" do
      it "prints error message" do
        expect { presenter.output_error(error, "text") }
          .to output(/something broke/).to_stdout
      end
    end

    context "with json format" do
      it "outputs valid JSON with error status" do
        json = capture_stdout { presenter.output_error(error, "json") }
        parsed = JSON.parse(json)

        aggregate_failures do
          expect(parsed["migration_guard"]["status"]).to eq("error")
          expect(parsed["migration_guard"]["error"]).to eq("something broke")
        end
      end
    end
  end

  private

  def capture_stdout
    output = StringIO.new
    original_stdout = $stdout
    $stdout = output
    yield
    output.string
  ensure
    $stdout = original_stdout
  end
end
