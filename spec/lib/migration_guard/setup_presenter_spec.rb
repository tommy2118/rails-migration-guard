# frozen_string_literal: true

require "rails_helper"
require_relative "../../../lib/migration_guard/setup_presenter"

RSpec.describe MigrationGuard::SetupPresenter do
  let(:output) { StringIO.new }
  let(:presenter) { described_class.new(output: output) }

  before do
    allow(MigrationGuard::Colorizer).to receive(:colorize_output?).and_return(false)
  end

  describe "#print_welcome_header" do
    it "includes welcome message and separator" do
      presenter.print_welcome_header

      aggregate_failures do
        expect(output.string).to include("Welcome to Rails Migration Guard Setup!")
        expect(output.string).to include("=" * 60)
      end
    end
  end

  describe "#print_summary" do
    context "with no issues" do
      it "includes success message and capability bullets" do
        presenter.print_summary([])

        aggregate_failures do
          expect(output.string).to include("Everything looks good!")
          expect(output.string).to include("Track migrations across branches")
          expect(output.string).to include("Detect orphaned migrations")
          expect(output.string).to include("Coordinate with your team")
        end
      end
    end

    context "with issues" do
      let(:issues) do
        [
          ["Missing table", "The migration_guard_records table does not exist"],
          ["Git not configured", "Git user.email is not set"]
        ]
      end

      it "includes issue count and details" do
        presenter.print_summary(issues)

        aggregate_failures do
          expect(output.string).to include("2 issue(s) found")
          expect(output.string).to include("1. Missing table")
          expect(output.string).to include("The migration_guard_records table does not exist")
          expect(output.string).to include("2. Git not configured")
        end
      end
    end
  end

  describe "#offer_interactive_fixes" do
    context "with empty suggestions" do
      it "returns nil" do
        result = presenter.offer_interactive_fixes([])

        expect(result).to be_nil
      end
    end

    context "when user accepts" do
      let(:suggestions) do
        [[:run_migrations, "Run pending migrations"]]
      end

      it "prints suggestions and returns true" do
        allow($stdin).to receive(:gets).and_return("y\n")

        result = presenter.offer_interactive_fixes(suggestions)

        aggregate_failures do
          expect(output.string).to include("Recommended Actions")
          expect(output.string).to include("1. Run pending migrations")
          expect(result).to be true
        end
      end
    end

    context "when user declines" do
      let(:suggestions) do
        [[:run_migrations, "Run pending migrations"]]
      end

      it "returns false" do
        allow($stdin).to receive(:gets).and_return("n\n")

        expect(presenter.offer_interactive_fixes(suggestions)).to be false
      end
    end
  end

  describe "#print_helpful_commands" do
    it "includes rake commands and happy coding message" do
      presenter.print_helpful_commands

      aggregate_failures do
        expect(output.string).to include("rails db:migration:status")
        expect(output.string).to include("rails db:migration:doctor")
        expect(output.string).to include("rails db:migration:history")
        expect(output.string).to include("rails db:migration:authors")
        expect(output.string).to include("Happy coding!")
      end
    end
  end
end
