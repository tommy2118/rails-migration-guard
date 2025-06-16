# frozen_string_literal: true

require "rails_helper"

RSpec.describe MigrationGuard::Recovery::OptionFormatter do
  describe ".format" do
    context "with known options" do
      it "returns correct description for complete_rollback" do
        result = described_class.format(:complete_rollback)
        expect(result).to eq("Complete the rollback (remove remaining schema/data changes)")
      end

      it "returns correct description for restore_migration" do
        result = described_class.format(:restore_migration)
        expect(result).to eq("Restore migration (re-apply schema changes)")
      end

      it "returns correct description for mark_as_rolled_back" do
        result = described_class.format(:mark_as_rolled_back)
        expect(result).to eq("Mark as rolled back (update status only)")
      end

      it "returns correct description for track_migration" do
        result = described_class.format(:track_migration)
        expect(result).to eq("Track this migration in Migration Guard")
      end

      it "returns correct description for remove_from_schema" do
        result = described_class.format(:remove_from_schema)
        expect(result).to eq("Remove from schema_migrations table")
      end

      it "returns correct description for reapply_migration" do
        result = described_class.format(:reapply_migration)
        expect(result).to eq("Re-apply the migration")
      end

      it "returns correct description for restore_from_git" do
        result = described_class.format(:restore_from_git)
        expect(result).to eq("Restore migration file from git history")
      end

      it "returns correct description for consolidate_records" do
        result = described_class.format(:consolidate_records)
        expect(result).to eq("Consolidate duplicate records into one")
      end

      it "returns correct description for remove_duplicates" do
        result = described_class.format(:remove_duplicates)
        expect(result).to eq("Remove duplicate tracking records")
      end
    end

    context "with unknown options" do
      it "returns humanized version for unknown symbol" do
        result = described_class.format(:some_unknown_option)
        expect(result).to eq("Some unknown option")
      end

      it "returns humanized version for snake_case symbol" do
        result = described_class.format(:custom_recovery_action)
        expect(result).to eq("Custom recovery action")
      end
    end

    context "with edge cases" do
      it "handles string input" do
        result = described_class.format("complete_rollback")
        expect(result).to eq("Complete rollback")
      end

      it "handles nil input gracefully" do
        result = described_class.format(nil)
        expect(result).to eq("")
      end
    end

    context "when checking all defined options" do
      it "has descriptions for all defined options" do
        described_class::OPTION_DESCRIPTIONS.each do |option, description|
          expect(description).to be_a(String)
          expect(description).not_to be_empty
          expect(described_class.format(option)).to eq(description)
        end
      end
    end

    context "when checking OPTION_DESCRIPTIONS constant" do
      it "is frozen" do
        expect(described_class::OPTION_DESCRIPTIONS).to be_frozen
      end

      it "contains expected recovery options" do
        expected_options = %i[
          complete_rollback
          restore_migration
          mark_as_rolled_back
          track_migration
          remove_from_schema
          reapply_migration
          restore_from_git
          consolidate_records
          remove_duplicates
        ]

        expect(described_class::OPTION_DESCRIPTIONS.keys).to include(*expected_options)
      end

      it "has no empty descriptions" do
        described_class::OPTION_DESCRIPTIONS.each do |option, description|
          expect(description).not_to be_empty, "Option #{option} has empty description"
        end
      end
    end
  end
end
