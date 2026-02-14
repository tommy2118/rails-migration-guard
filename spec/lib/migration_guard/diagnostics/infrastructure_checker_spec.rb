# frozen_string_literal: true

require "rails_helper"

RSpec.describe MigrationGuard::Diagnostics::InfrastructureChecker do
  let(:issues) { [] }
  let(:warnings) { [] }
  let(:io) { StringIO.new }
  let(:checker) { described_class.new(issues: issues, warnings: warnings, output: io) }

  before do
    allow(MigrationGuard::Colorizer).to receive(:colorize_output?).and_return(false)
  end

  describe "#run_checks" do
    describe "database connection" do
      it "reports success when connected" do
        checker.run_checks

        expect(io.string).to include("Database connection")
      end

      context "when connection fails" do
        before do
          allow(ActiveRecord::Base.connection).to receive(:execute).and_call_original
          allow(ActiveRecord::Base.connection).to receive(:execute).with("SELECT 1")
                                                                   .and_raise(StandardError, "Connection failed")
        end

        it "adds an issue" do
          checker.run_checks

          aggregate_failures do
            expect(io.string).to include("Database connection")
            expect(issues).to include(["Database connection failed",
                                       "Check your database configuration: Connection failed"])
          end
        end
      end
    end

    describe "migration guard tables" do
      it "reports record count on success" do
        checker.run_checks

        expect(io.string).to include("Migration guard tables")
        expect(io.string).to include("records")
      end

      context "when tables are missing" do
        before do
          allow(MigrationGuard::MigrationGuardRecord).to receive(:table_exists?).and_return(false)
          allow(MigrationGuard::MigrationGuardRecord).to receive(:count).and_raise(StandardError, "Table missing")
        end

        it "adds an issue" do
          checker.run_checks

          expect(issues).to include(["Migration guard tables missing",
                                     "Run 'rails generate migration_guard:install' and 'rails db:migrate'"])
        end
      end
    end

    describe "environment configuration" do
      context "when enabled in current environment" do
        before do
          allow(MigrationGuard.configuration).to receive(:enabled_environments).and_return([:test])
        end

        it "reports success" do
          checker.run_checks

          expect(io.string).to include("Environment configuration")
          expect(io.string).to include("enabled in: test")
        end
      end

      context "when disabled in current environment" do
        before do
          allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
        end

        it "adds a warning" do
          checker.run_checks

          aggregate_failures do
            expect(io.string).to include("disabled in production")
            expect(warnings.flatten).to include("MigrationGuard disabled in current environment")
          end
        end
      end

      context "when Rails is not loaded" do
        before { hide_const("Rails") }

        it "adds a warning" do
          checker.run_checks

          aggregate_failures do
            expect(io.string).to include("Rails not loaded")
            expect(warnings.flatten).to include("Rails environment not detected")
          end
        end
      end
    end

    describe "sandbox mode" do
      context "when enabled" do
        before do
          allow(MigrationGuard.configuration).to receive(:sandbox_mode).and_return(true)
        end

        it "adds a warning" do
          checker.run_checks

          aggregate_failures do
            expect(io.string).to include("ACTIVE (changes will be rolled back)")
            expect(warnings.flatten).to include("Sandbox mode is enabled")
          end
        end
      end

      context "when disabled" do
        before do
          allow(MigrationGuard.configuration).to receive(:sandbox_mode).and_return(false)
        end

        it "reports success" do
          checker.run_checks

          expect(io.string).to include("Sandbox mode: disabled")
        end
      end
    end
  end
end
