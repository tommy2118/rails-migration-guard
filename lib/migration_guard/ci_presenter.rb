# frozen_string_literal: true

# rubocop:disable Rails/Output
module MigrationGuard
  # Formats CI runner results for text and JSON output
  class CiPresenter
    def output_result(result, format, strictness)
      case format
      when "json"
        output_json(result, strictness)
      else
        output_text(result, strictness)
      end
    end

    def output_disabled_message(format)
      message = {
        status: "disabled",
        message: "MigrationGuard is not enabled in #{Rails.env} environment",
        exit_code: CiRunner::EXIT_SUCCESS
      }

      case format
      when "json"
        puts JSON.pretty_generate(migration_guard: message)
      else
        puts "\u{2139}\u{FE0F}  MigrationGuard is not enabled in #{Rails.env} environment"
      end
    end

    def output_error(error, format)
      error_info = {
        status: "error",
        error: error.message,
        backtrace: error.backtrace&.first(5),
        exit_code: CiRunner::EXIT_ERROR
      }

      case format
      when "json"
        puts JSON.pretty_generate(migration_guard: error_info)
      else
        puts "\u{274C} Error running Migration Guard CI check:"
        puts "   #{error.message}"
        puts ""
        puts "For debugging, run with more verbose logging or check your configuration."
      end
    end

    private

    def output_json(result, strictness)
      json_output = {
        migration_guard: {
          version: MigrationGuard::VERSION,
          status: result[:status],
          summary: result[:summary],
          orphaned_migrations: result[:orphaned_migrations],
          missing_migrations: result[:missing_migrations],
          branch_info: result[:branch_info],
          timestamp: result[:timestamp],
          exit_code: determine_exit_code(result, strictness),
          strictness: strictness
        }
      }

      puts JSON.pretty_generate(json_output)
    end

    def output_text(result, strictness)
      puts format_text_header(result)
      puts ""

      if result[:summary][:issues_found].positive?
        output_text_issues(result)
      else
        puts "\u{2705} No migration issues found"
      end

      puts ""
      output_text_summary(result, strictness)
    end

    def format_text_header(result)
      status_emoji = {
        "success" => "✅",
        "warning" => "⚠️ ",
        "error" => "❌"
      }[result[:status]]

      branch_info = result[:branch_info]
      "#{status_emoji} Migration Guard CI Check (#{branch_info[:current]} → #{branch_info[:main]})"
    end

    # rubocop:disable Metrics/AbcSize
    def output_text_issues(result)
      if result[:orphaned_migrations].any?
        puts "\u{1F50D} Orphaned Migrations Found:"
        result[:orphaned_migrations].each do |migration|
          puts "  • #{migration[:version]} (#{migration[:branch]}) - #{migration[:author]}"
        end
        puts ""
      end

      if result[:missing_migrations].any?
        puts "\u{1F4E5} Missing Migrations:"
        result[:missing_migrations].each do |migration|
          puts "  • #{migration[:version]} (exists in #{result[:branch_info][:main]})"
        end
        puts ""
      end

      output_text_recommendations(result)
    end
    # rubocop:enable Metrics/AbcSize

    # rubocop:disable Metrics/AbcSize
    def output_text_recommendations(result)
      puts "\u{1F4A1} Recommended Actions:"

      if result[:orphaned_migrations].any?
        puts "  1. Roll back orphaned migrations:"
        result[:orphaned_migrations].each do |migration|
          puts "     rails db:migration:rollback_specific VERSION=#{migration[:version]}"
        end
        puts "  2. Or commit migration files if they should be included"
      end

      return unless result[:missing_migrations].any?

      puts "  1. Pull latest changes from #{result[:branch_info][:main]}:"
      puts "     git pull origin #{result[:branch_info][:main]}"
      puts "  2. Run migrations:"
      puts "     rails db:migrate"
    end
    # rubocop:enable Metrics/AbcSize

    def output_text_summary(result, strictness)
      summary = result[:summary]
      puts "\u{1F4CA} Summary:"
      puts "   Orphaned: #{summary[:total_orphaned]}"
      puts "   Missing: #{summary[:total_missing]}"
      puts "   Strictness: #{strictness}"
      puts "   Exit code: #{determine_exit_code(result, strictness)}"
    end

    def determine_exit_code(result, strictness)
      case result[:status]
      when "success"
        CiRunner::EXIT_SUCCESS
      when "warning"
        strictness == "strict" ? CiRunner::EXIT_ERROR : CiRunner::EXIT_WARNING
      else
        CiRunner::EXIT_ERROR
      end
    end
  end
end
# rubocop:enable Rails/Output
