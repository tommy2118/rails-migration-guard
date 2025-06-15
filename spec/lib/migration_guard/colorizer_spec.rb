# frozen_string_literal: true

require "rails_helper"

RSpec.describe MigrationGuard::Colorizer do
  describe ".colorize_output?" do
    context "when NO_COLOR environment variable is set" do
      before do
        allow(ENV).to receive(:[]).with("NO_COLOR").and_return("1")
      end

      it "returns false" do
        expect(described_class.colorize_output?).to be false
      end
    end

    context "when colorize_output is disabled in configuration" do
      before do
        allow(ENV).to receive(:[]).with("NO_COLOR").and_return(nil)
        allow(MigrationGuard.configuration).to receive(:colorize_output).and_return(false)
      end

      it "returns false" do
        expect(described_class.colorize_output?).to be false
      end
    end

    context "when output is not a TTY" do
      before do
        allow(ENV).to receive(:[]).with("NO_COLOR").and_return(nil)
        allow(MigrationGuard.configuration).to receive(:colorize_output).and_return(true)
        allow($stdout).to receive(:tty?).and_return(false)
      end

      it "returns false" do
        expect(described_class.colorize_output?).to be false
      end
    end

    context "when all conditions are met for color output" do
      before do
        allow(ENV).to receive(:[]).with("NO_COLOR").and_return(nil)
        allow(MigrationGuard.configuration).to receive(:colorize_output).and_return(true)
        allow($stdout).to receive(:tty?).and_return(true)
      end

      it "returns true" do
        expect(described_class.colorize_output?).to be true
      end
    end
  end

  describe "color methods" do
    context "when colorize is enabled" do
      before do
        allow(described_class).to receive(:colorize_output?).and_return(true)
      end

      describe ".success" do
        it "returns green text" do
          result = described_class.success("Success!")
          expect(result).to eq(Rainbow("Success!").green)
        end
      end

      describe ".warning" do
        it "returns yellow text" do
          result = described_class.warning("Warning!")
          expect(result).to eq(Rainbow("Warning!").yellow)
        end
      end

      describe ".error" do
        it "returns red text" do
          result = described_class.error("Error!")
          expect(result).to eq(Rainbow("Error!").red)
        end
      end

      describe ".info" do
        it "returns cyan text" do
          result = described_class.info("Info!")
          expect(result).to eq(Rainbow("Info!").cyan)
        end
      end

      describe ".bold" do
        it "returns bright text" do
          result = described_class.bold("Bold!")
          expect(result).to eq(Rainbow("Bold!").bright)
        end
      end
    end

    context "when colorize is disabled" do
      before do
        allow(described_class).to receive(:colorize_output?).and_return(false)
      end

      describe ".success" do
        it "returns unformatted text" do
          expect(described_class.success("Success!")).to eq("Success!")
        end
      end

      describe ".warning" do
        it "returns unformatted text" do
          expect(described_class.warning("Warning!")).to eq("Warning!")
        end
      end

      describe ".error" do
        it "returns unformatted text" do
          expect(described_class.error("Error!")).to eq("Error!")
        end
      end

      describe ".info" do
        it "returns unformatted text" do
          expect(described_class.info("Info!")).to eq("Info!")
        end
      end

      describe ".bold" do
        it "returns unformatted text" do
          expect(described_class.bold("Bold!")).to eq("Bold!")
        end
      end
    end
  end

  describe "formatting methods" do
    context "when colorize is enabled" do
      before do
        allow(described_class).to receive(:colorize_output?).and_return(true)
      end

      describe ".format_checkmark" do
        it "returns green checkmark" do
          expect(described_class.format_checkmark).to eq(Rainbow("✓").green)
        end
      end

      describe ".format_warning_symbol" do
        it "returns yellow warning symbol" do
          expect(described_class.format_warning_symbol).to eq(Rainbow("⚠").yellow)
        end
      end

      describe ".format_error_symbol" do
        it "returns red error symbol" do
          expect(described_class.format_error_symbol).to eq(Rainbow("✗").red)
        end
      end

      describe ".format_migration_count" do
        it "formats synced count in green" do
          result = described_class.format_migration_count(5, :synced)
          expect(result).to eq(Rainbow("5 migrations").green)
        end

        it "formats orphaned count in yellow" do
          result = described_class.format_migration_count(2, :orphaned)
          expect(result).to eq(Rainbow("2 migrations").yellow)
        end

        it "formats missing count in red" do
          result = described_class.format_migration_count(1, :missing)
          expect(result).to eq(Rainbow("1 migration").red)
        end

        it "returns uncolored text for unknown type" do
          result = described_class.format_migration_count(3, :unknown)
          expect(result).to eq("3 migrations")
        end

        it "uses singular form for count of 1" do
          result = described_class.format_migration_count(1, :synced)
          expect(result).to eq(Rainbow("1 migration").green)
        end
      end

      describe ".format_status_line" do
        it "formats a complete status line" do
          result = described_class.format_status_line("✓", "Synced", 10, :synced)
          expect(result).to eq("✓ Synced: #{Rainbow('10 migrations').green}")
        end
      end
    end

    context "when colorize is disabled" do
      before do
        allow(described_class).to receive(:colorize_output?).and_return(false)
      end

      describe ".format_checkmark" do
        it "returns plain checkmark" do
          expect(described_class.format_checkmark).to eq("✓")
        end
      end

      describe ".format_warning_symbol" do
        it "returns plain warning symbol" do
          expect(described_class.format_warning_symbol).to eq("⚠")
        end
      end

      describe ".format_error_symbol" do
        it "returns plain error symbol" do
          expect(described_class.format_error_symbol).to eq("✗")
        end
      end
    end
  end
end
