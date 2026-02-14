# frozen_string_literal: true

require_relative "colorizer"

module MigrationGuard
  # Formats author migration report data for display
  class AuthorPresenter
    # rubocop:disable Metrics/AbcSize
    def format_authors_report(authors_data, current_branch)
      return no_authors_message if authors_data.empty?

      output = []
      output << build_header(current_branch)
      output << build_table_header
      output << build_separator
      output << authors_data.map { |author_info| format_author_row(author_info) }
      output << build_separator
      output << build_summary(authors_data)

      output.flatten.join("\n")
    end
    # rubocop:enable Metrics/AbcSize

    private

    def build_header(current_branch)
      Colorizer.info("\u{1F465} Migration Authors Report (#{current_branch})")
    end

    def build_table_header
      "Author                           Total    Applied  Orphaned  Rolled Back  Latest Migration    "
    end

    def build_separator
      "-" * 95
    end

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def format_author_row(author_info)
      author_name = truncate_string(author_info[:author] || "unknown", 30)
      latest_date = author_info[:latest_migration]&.strftime("%Y-%m-%d %H:%M") || "Never"

      total_colored = Colorizer.info(author_info[:total].to_s)
      applied_colored = author_info[:applied].positive? ? Colorizer.success(author_info[:applied].to_s) : "0"
      orphaned_colored = author_info[:orphaned].positive? ? Colorizer.error(author_info[:orphaned].to_s) : "0"
      rolled_back_colored = if author_info[:rolled_back].positive?
                              Colorizer.warning(author_info[:rolled_back].to_s)
                            else
                              "0"
                            end

      # rubocop:disable Style/FormatStringToken
      format(
        "%-30s %8s %8s %9s %12s %19s",
        author_name,
        total_colored,
        applied_colored,
        orphaned_colored,
        rolled_back_colored,
        latest_date
      )
      # rubocop:enable Style/FormatStringToken
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    def build_summary(authors_data)
      total_authors = authors_data.count
      total_migrations = authors_data.sum { |a| a[:total] }
      most_active = authors_data.first

      summary = []
      summary << ""
      summary << Colorizer.info("\u{1F4CA} Authors Summary:")
      summary << "  Total authors: #{total_authors}"
      summary << "  Total tracked migrations: #{total_migrations}"

      if most_active
        summary << "  Most active: #{most_active[:author]} (#{most_active[:total]} migrations)"
        summary << "  Average per author: #{(total_migrations.to_f / total_authors).round(1)}"
      end

      summary
    end

    def no_authors_message
      message = "No migration authors found.\n\n"
      message += "This could mean:\n"
      message += "  - Author tracking is disabled (config.track_author = false)\n"
      message += "  - No migrations have been tracked yet\n"
      message += "  - Git user.email is not configured\n\n"
      message += "To enable author tracking:\n"
      message += "  1. Set config.track_author = true in your initializer\n"
      message += "  2. Configure git: git config user.email 'your@email.com'\n"
      message += "  3. Run migrations to start tracking"

      Colorizer.warning(message)
    end

    def truncate_string(string, length)
      return string if string.length <= length

      "#{string[0..(length - 4)]}..."
    end
  end
end
