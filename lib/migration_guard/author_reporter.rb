# frozen_string_literal: true

require "migration_guard/colorizer"

module MigrationGuard
  # AuthorReporter provides author-focused migration reports and analysis
  class AuthorReporter
    def initialize
      @git_integration = GitIntegration.new
    end

    # rubocop:disable Metrics/AbcSize
    def format_authors_report
      authors_data = collect_authors_data
      return no_authors_message if authors_data.empty?

      output = []
      output << build_header
      output << build_table_header
      output << build_separator
      output << authors_data.map { |author_info| format_author_row(author_info) }
      output << build_separator
      output << build_summary(authors_data)

      output.flatten.join("\n")
    end
    # rubocop:enable Metrics/AbcSize

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    def collect_authors_data
      records = MigrationGuardRecord.where.not(author: [nil, ""])

      authors_stats = records.group(:author).group(:status).count
      authors_latest = records.group(:author).maximum(:created_at)

      authors_summary = {}

      authors_stats.each do |(author, status), count|
        authors_summary[author] ||= {
          author: author,
          total: 0,
          applied: 0,
          rolled_back: 0,
          orphaned: 0,
          synced: 0,
          rolling_back: 0,
          latest_migration: authors_latest[author]
        }

        authors_summary[author][:total] += count
        # Ensure the status key exists before incrementing
        authors_summary[author][status.to_sym] ||= 0
        authors_summary[author][status.to_sym] += count
      end

      # Sort by total migrations, then by latest activity
      authors_summary.values.sort do |a, b|
        comparison = b[:total] <=> a[:total]
        if comparison.zero?
          (b[:latest_migration] || Time.zone.at(0)) <=> (a[:latest_migration] || Time.zone.at(0))
        else
          comparison
        end
      end
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

    private

    def build_header
      current_branch = begin
        @git_integration.current_branch
      rescue StandardError
        "unknown"
      end
      Colorizer.info("👥 Migration Authors Report (#{current_branch})")
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

      # Colorize counts based on status
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

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def build_summary(authors_data)
      total_authors = authors_data.count
      total_migrations = authors_data.sum { |a| a[:total] }
      most_active = authors_data.first

      summary = []
      summary << ""
      summary << Colorizer.info("📊 Authors Summary:")
      summary << "  Total authors: #{total_authors}"
      summary << "  Total tracked migrations: #{total_migrations}"

      if most_active
        summary << "  Most active: #{most_active[:author]} (#{most_active[:total]} migrations)"
        summary << "  Average per author: #{(total_migrations.to_f / total_authors).round(1)}"
      end

      # Show current user's position if available
      current_user = current_user_email
      if current_user
        user_data = authors_data.find { |a| a[:author]&.include?(current_user) }
        if user_data
          rank = authors_data.index(user_data) + 1
          summary << "  Your rank: ##{rank} (#{user_data[:total]} migrations)"
        else
          summary << "  Your contributions: No tracked migrations found"
        end
      end

      summary
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

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

    def current_user_email
      @git_integration.current_author
    rescue StandardError
      nil
    end

    def truncate_string(string, length)
      return string if string.length <= length

      "#{string[0..(length - 4)]}..."
    end
  end
end
