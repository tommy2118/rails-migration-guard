# frozen_string_literal: true

require "migration_guard/colorizer"
require_relative "history_presenter"

module MigrationGuard
  # Historian provides migration history reporting and analysis
  class Historian
    DEFAULT_LIMIT = 50
    SUPPORTED_FORMATS = %w[table json csv].freeze

    def initialize(options = {})
      @options = options
      @branch_filter = options[:branch]
      @days_filter = options[:days]
      @version_filter = options[:version]
      @author_filter = options[:author]
      @limit = options[:limit] || DEFAULT_LIMIT
      @format = options[:format] || "table"

      validate_options!
    end

    def format_history_output
      presenter = HistoryPresenter.new

      case @format.downcase
      when "json"
        presenter.format_json_output(migration_history.to_a, calculate_statistics, active_filters)
      when "csv"
        presenter.format_csv_output(migration_history.to_a)
      else
        presenter.format_table_output(
          migration_history.to_a,
          method(:calculate_statistics_for_records),
          filters_applied?,
          active_filters
        )
      end
    end

    def migration_history
      @migration_history ||= build_query.limit(@limit)
    end

    def statistics
      @statistics ||= calculate_statistics
    end

    private

    # rubocop:disable Metrics/CyclomaticComplexity
    def validate_options!
      unless SUPPORTED_FORMATS.include?(@format)
        raise ArgumentError, "Unsupported format: #{@format}. Supported: #{SUPPORTED_FORMATS.join(', ')}"
      end

      raise ArgumentError, "Limit must be between 1 and 1000" if @limit && (@limit <= 0 || @limit > 1000)

      return unless @days_filter && (@days_filter <= 0 || @days_filter > 365)

      raise ArgumentError, "Days filter must be between 1 and 365"
    end
    # rubocop:enable Metrics/CyclomaticComplexity

    def build_query
      query = MigrationGuardRecord.history_ordered

      query = query.for_branch(@branch_filter) if @branch_filter
      query = query.within_days(@days_filter) if @days_filter
      query = query.for_version(@version_filter) if @version_filter
      query = query.for_author(@author_filter) if @author_filter

      query
    end

    def calculate_statistics
      calculate_statistics_for_records(MigrationGuardRecord.all)
    end

    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    def calculate_statistics_for_records(records)
      total = records.count
      active_statuses = [MigrationGuardRecord::STATUS_APPLIED, MigrationGuardRecord::STATUS_SYNCED]
      applied = records.count { |r| active_statuses.include?(r.status) }
      rolled_back = records.count { |r| r.status == MigrationGuardRecord::STATUS_ROLLED_BACK }
      orphaned = records.count { |r| r.status == MigrationGuardRecord::STATUS_ORPHANED }
      branches = records.map(&:branch).compact.uniq

      date_range = if records.any?
                     oldest = records.map(&:created_at).min
                     newest = records.map(&:created_at).max
                     "#{oldest.strftime('%Y-%m-%d')} to #{newest.strftime('%Y-%m-%d')}"
                   else
                     "No records"
                   end

      {
        total: total,
        applied: applied,
        rolled_back: rolled_back,
        orphaned: orphaned,
        branches: branches,
        date_range: date_range
      }
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

    def active_filters
      filters = {}
      filters[:branch] = @branch_filter if @branch_filter
      filters[:version] = @version_filter if @version_filter
      filters[:author] = @author_filter if @author_filter
      filters[:days] = @days_filter if @days_filter
      filters[:limit] = @limit if @limit != DEFAULT_LIMIT
      filters
    end

    def filters_applied?
      @branch_filter || @version_filter || @author_filter || @days_filter || (@limit != DEFAULT_LIMIT)
    end
  end
end
