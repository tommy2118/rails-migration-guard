# frozen_string_literal: true

require "rails_helper"

RSpec.describe MigrationGuard::DiagnosticPresenter do
  let(:output) { StringIO.new }
  let(:presenter) { described_class.new(output: output) }

  before do
    allow(MigrationGuard::Colorizer).to receive(:colorize_output?).and_return(false)
  end

  describe "#print_header" do
    it "includes diagnostics message" do
      presenter.print_header

      expect(output.string).to include("Running Migration Guard Diagnostics...")
    end
  end

  describe "#print_summary" do
    context "with issues" do
      it "includes numbered issue titles" do
        issues = [["Schema mismatch", "Applied migration missing from schema"]]

        presenter.print_summary(issues, [])

        aggregate_failures do
          expect(output.string).to include("Issues Found:")
          expect(output.string).to include("1. Schema mismatch:")
          expect(output.string).to include("Applied migration missing from schema")
        end
      end
    end

    context "with warnings" do
      it "includes numbered warning titles" do
        warnings = [["Untracked migration", "Migration in schema but not tracked"]]

        presenter.print_summary([], warnings)

        aggregate_failures do
          expect(output.string).to include("Warnings:")
          expect(output.string).to include("1. Untracked migration:")
        end
      end
    end

    context "with neither issues nor warnings" do
      it "includes all-systems-ok message" do
        presenter.print_summary([], [])

        expect(output.string).to include("ALL SYSTEMS OK")
      end
    end
  end

  describe "#print_overall_status" do
    context "with issues" do
      it "prints needs-attention with count" do
        issues = [["Issue 1", "desc"], ["Issue 2", "desc"]]

        presenter.print_overall_status(issues, [])

        expect(output.string).to include("NEEDS ATTENTION (2 issue(s))")
      end
    end

    context "with warnings only" do
      it "prints ok-with-warnings with count" do
        presenter.print_overall_status([], [["Warning 1", "desc"]])

        expect(output.string).to include("OK WITH WARNINGS (1 warning(s))")
      end
    end

    context "when clean" do
      it "prints all-systems-ok" do
        presenter.print_overall_status([], [])

        expect(output.string).to include("ALL SYSTEMS OK")
      end
    end
  end
end
