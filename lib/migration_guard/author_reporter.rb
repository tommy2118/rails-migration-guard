# frozen_string_literal: true

require "migration_guard/colorizer"
require_relative "author_presenter"

module MigrationGuard
  # AuthorReporter provides author-focused migration reports and analysis
  class AuthorReporter
    def initialize(git_integration: GitIntegration.new)
      @git_integration = git_integration
    end

    def format_authors_report
      authors_data = collect_authors_data
      current_branch = safe_current_branch
      presenter = AuthorPresenter.new
      result = presenter.format_authors_report(authors_data, current_branch)
      append_user_rank(result, authors_data)
    end

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
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
          latest_migration: authors_latest[author]
        }

        authors_summary[author][:total] += count
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
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    private

    def safe_current_branch
      @git_integration.current_branch
    rescue StandardError
      "unknown"
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

    def append_user_rank(report, authors_data)
      return report if authors_data.empty?

      current_user = current_user_email
      return report unless current_user

      user_data = authors_data.find { |a| a[:author]&.include?(current_user) }
      if user_data
        rank = authors_data.index(user_data) + 1
        "#{report}\n  Your rank: ##{rank} (#{user_data[:total]} migrations)"
      else
        "#{report}\n  Your contributions: No tracked migrations found"
      end
    end
  end
end
