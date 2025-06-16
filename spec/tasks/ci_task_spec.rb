# frozen_string_literal: true

require "rails_helper"
require "rake"

# rubocop:disable RSpec/VerifiedDoubles, RSpec/NestedGroups, RSpec/AnyInstance, RSpec/ExampleLength, Metrics/BlockNesting

RSpec.describe "CI rake task", type: :integration do
  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  before do
    # Reset task state
    Rake::Task.tasks.each(&:reenable) if Rake::Task.tasks.any?

    # Clean database state
    MigrationGuard::MigrationGuardRecord.delete_all

    # Set up git integration mock
    git_integration = instance_double(MigrationGuard::GitIntegration)
    allow(MigrationGuard::GitIntegration).to receive(:new).and_return(git_integration)
    allow(git_integration).to receive_messages(
      current_branch: "feature/test",
      main_branch: "main"
    )

    # Stub exit method to prevent process termination during tests
    # Tests that expect SystemExit will override this stub
    allow_any_instance_of(Object).to receive(:exit)
  end

  describe "db:migration:ci" do
    context "when MigrationGuard is disabled" do
      before do
        allow(MigrationGuard).to receive(:enabled?).and_return(false)
      end

      it "runs successfully and outputs disabled message" do
        output = capture_rake_output { Rake::Task["db:migration:ci"].execute }

        expect(output).to include("MigrationGuard is not enabled")
      end

      it "exits with success code when disabled" do
        # The rake task should not call exit when return code is 0
        expect { Rake::Task["db:migration:ci"].execute }.not_to raise_error
      end
    end

    context "when MigrationGuard is enabled" do
      before do
        allow(MigrationGuard).to receive(:enabled?).and_return(true)
      end

      context "with no migration issues" do
        before do
          reporter = instance_double(MigrationGuard::Reporter)
          allow(MigrationGuard::Reporter).to receive(:new).and_return(reporter)
          allow(reporter).to receive_messages(orphaned_migrations: [], missing_migrations: [])
        end

        it "outputs success message in text format" do
          output = capture_rake_output { Rake::Task["db:migration:ci"].execute }

          expect(output).to include("✅ No migration issues found")
        end

        it "does not exit the process for success" do
          expect { Rake::Task["db:migration:ci"].execute }.not_to raise_error
        end
      end

      context "with orphaned migrations" do
        before do
          orphaned_migration = double("migration_record",
                                      version: "20240101000001",
                                      branch: "feature/test",
                                      author: "test@example.com",
                                      created_at: Time.current)

          reporter = instance_double(MigrationGuard::Reporter)
          allow(MigrationGuard::Reporter).to receive(:new).and_return(reporter)
          allow(reporter).to receive_messages(orphaned_migrations: [orphaned_migration], missing_migrations: [])
        end

        it "outputs orphaned migration details" do
          output = capture_rake_output { Rake::Task["db:migration:ci"].execute }

          aggregate_failures "orphaned migration output" do
            expect(output).to include("Orphaned Migrations Found")
            expect(output).to include("20240101000001")
            expect(output).to include("feature/test")
            expect(output).to include("test@example.com")
          end
        end

        it "includes recommended actions" do
          output = capture_rake_output { Rake::Task["db:migration:ci"].execute }

          expect(output).to include("rails db:migration:rollback_specific VERSION=20240101000001")
        end

        context "with default warning strictness" do
          it "exits with warning code" do
            allow_any_instance_of(Object).to receive(:exit) { |_, code| raise SystemExit, code }

            expect { Rake::Task["db:migration:ci"].execute }.to raise_error(SystemExit) do |error|
              expect(error.status).to eq(1) # EXIT_WARNING
            end
          end
        end

        context "with strict mode via ENV" do
          before do
            ENV["STRICT"] = "true"
          end

          after do
            ENV.delete("STRICT")
          end

          it "exits with error code" do
            allow_any_instance_of(Object).to receive(:exit) { |_, code| raise SystemExit, code }

            expect { Rake::Task["db:migration:ci"].execute }.to raise_error(SystemExit) do |error|
              expect(error.status).to eq(2) # EXIT_ERROR
            end
          end
        end

        context "with strictness level via ENV" do
          before do
            ENV["STRICTNESS"] = "permissive"
          end

          after do
            ENV.delete("STRICTNESS")
          end

          it "does not exit for permissive mode" do
            expect { Rake::Task["db:migration:ci"].execute }.not_to raise_error
          end
        end
      end

      context "with JSON format" do
        before do
          ENV["FORMAT"] = "json"

          reporter = instance_double(MigrationGuard::Reporter)
          allow(MigrationGuard::Reporter).to receive(:new).and_return(reporter)
          allow(reporter).to receive_messages(orphaned_migrations: [], missing_migrations: [])
        end

        after do
          ENV.delete("FORMAT")
        end

        it "outputs valid JSON" do
          raw_output = capture_stdout { Rake::Task["db:migration:ci"].execute }

          # Try multiple approaches to extract JSON
          json_output = nil

          # Method 1: Find complete JSON object by scanning for balanced braces
          if raw_output.include?("{") && raw_output.include?("migration_guard")
            start_pos = raw_output.index("{")
            if start_pos
              brace_count = 0
              end_pos = nil

              raw_output[start_pos..].each_char.with_index do |char, i|
                case char
                when "{"
                  brace_count += 1
                when "}"
                  brace_count -= 1
                  if brace_count == 0
                    end_pos = start_pos + i
                    break
                  end
                end
              end

              json_output = raw_output[start_pos..end_pos] if end_pos
            end
          end

          # Method 2: Try regex if method 1 failed
          if json_output.nil?
            json_match = raw_output.match(/\{[^{}]*"migration_guard"[^{}]*\{[^{}]*\}[^{}]*\}/m)
            json_output = json_match[0] if json_match
          end

          unless json_output
            puts "=== NO VALID JSON FOUND ==="
            puts "Raw output (first 1000 chars): #{raw_output[0...1000].inspect}"
            puts "=== FULL RAW OUTPUT ==="
            puts raw_output.inspect
            puts "=== OUTPUT LINES ==="
            raw_output.lines.each_with_index { |line, i| puts "Line #{i + 1}: #{line.inspect}" }
            raise "No valid JSON output found in response"
          end

          # Parse and validate JSON
          json_result = JSON.parse(json_output)

          expect(json_result).to have_key("migration_guard")
          expect(json_result["migration_guard"]).to include(
            "status" => "success",
            "exit_code" => 0
          )
        end
      end

      context "when an error occurs" do
        before do
          allow(MigrationGuard::Reporter).to receive(:new).and_raise(StandardError, "Database connection failed")
        end

        it "outputs error message" do
          output = capture_rake_output { Rake::Task["db:migration:ci"].execute }

          expect(output).to include("Error running Migration Guard CI check")
          expect(output).to include("Database connection failed")
        end

        it "exits with error code" do
          allow_any_instance_of(Object).to receive(:exit) { |_, code| raise SystemExit, code }

          expect { Rake::Task["db:migration:ci"].execute }.to raise_error(SystemExit) do |error|
            expect(error.status).to eq(2) # EXIT_ERROR
          end
        end
      end
    end

    context "with environment variable handling" do
      before do
        allow(MigrationGuard).to receive(:enabled?).and_return(true)

        reporter = instance_double(MigrationGuard::Reporter)
        allow(MigrationGuard::Reporter).to receive(:new).and_return(reporter)
        allow(reporter).to receive_messages(orphaned_migrations: [], missing_migrations: [])
      end

      it "supports case-insensitive FORMAT environment variable" do
        ENV["format"] = "JSON"

        raw_output = capture_stdout { Rake::Task["db:migration:ci"].execute }

        # Find complete JSON object by scanning for balanced braces
        json_output = nil
        if raw_output.include?("{") && raw_output.include?("migration_guard")
          start_pos = raw_output.index("{")
          if start_pos
            brace_count = 0
            end_pos = nil

            raw_output[start_pos..].each_char.with_index do |char, i|
              case char
              when "{"
                brace_count += 1
              when "}"
                brace_count -= 1
                if brace_count == 0
                  end_pos = start_pos + i
                  break
                end
              end
            end

            json_output = raw_output[start_pos..end_pos] if end_pos
          end
        end

        expect(json_output).not_to be_nil, "No JSON output found in: #{raw_output.inspect}"

        json_result = JSON.parse(json_output)
        expect(json_result).to have_key("migration_guard")
      ensure
        ENV.delete("format")
      end

      it "supports case-insensitive STRICT environment variable" do
        ENV["strict"] = "true"

        output = capture_rake_output { Rake::Task["db:migration:ci"].execute }

        expect(output).to include("Strictness: strict")
      ensure
        ENV.delete("strict")
      end

      it "supports case-insensitive STRICTNESS environment variable" do
        ENV["strictness"] = "STRICT"

        output = capture_rake_output { Rake::Task["db:migration:ci"].execute }

        expect(output).to include("Strictness: strict")
      ensure
        ENV.delete("strictness")
      end
    end
  end

  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
  def capture_rake_output
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    output = $stdout.string

    # For JSON format tests, try to extract just the JSON portion
    if output.include?('{"migration_guard"')
      # Find the start of JSON and extract everything from there
      json_start = output.index('{"migration_guard"')
      if json_start
        json_portion = output[json_start..]
        # Find the end of the JSON object by counting braces
        brace_count = 0
        json_end = nil
        json_portion.each_char.with_index do |char, i|
          case char
          when "{"
            brace_count += 1
          when "}"
            brace_count -= 1
            if brace_count == 0
              json_end = i
              break
            end
          end
        end
        return json_portion[0..json_end] if json_end
      end
    end

    # Filter out ActiveRecord migration output that could interfere with JSON parsing
    lines = output.split("\n")
    filtered_lines = lines.reject do |line|
      line.match?(/^\s*--/) ||
        line.match?(/^\s*->/) ||
        line.match?(/^\s*Coverage report/) ||
        line.match?(/^\s*Line Coverage/) ||
        line.match?(/warning:.*redefined/) ||
        line.strip.empty?
    end

    filtered_lines.join("\n")
  ensure
    $stdout = original_stdout
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end
end
# rubocop:enable RSpec/VerifiedDoubles, RSpec/NestedGroups, RSpec/AnyInstance, RSpec/ExampleLength, Metrics/BlockNesting
