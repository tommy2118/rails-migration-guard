# frozen_string_literal: true

require "migration_guard/colorizer"

module MigrationGuard
  # Historian provides migration history reporting and analysis
  # rubocop:disable Metrics/ClassLength
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
      case @format.downcase
      when "json"
        format_json_output
      when "csv"
        format_csv_output
      else
        format_table_output
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

    # rubocop:disable Metrics/AbcSize
    def format_table_output
      records = migration_history.to_a

      return no_records_message if records.empty?

      output = []
      output << build_header
      output << build_table_header
      output << build_separator
      output << records.map { |record| format_record_row(record) }
      output << build_separator
      output << build_summary(records)
      output << build_filters_info if filters_applied?

      output.flatten.join("\n")
    end
    # rubocop:enable Metrics/AbcSize

    def format_json_output
      records = migration_history.to_a

      {
        summary: calculate_statistics,
        filters: active_filters,
        history: records.map { |record| record_to_hash(record) }
      }.to_json
    end

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def format_csv_output
      begin
        require "csv"
      rescue LoadError
        return "CSV format requires the 'csv' gem. Please add it to your Gemfile."
      end

      records = migration_history.to_a

      CSV.generate do |csv|
        csv << ["Timestamp", "Version", "Migration", "Direction", "Status", "Branch", "Author", "Execution Time"]

        records.each do |record|
          csv << [
            record.created_at.strftime("%Y-%m-%d %H:%M:%S"),
            record.version,
            record.migration_file_name,
            record.direction,
            record.status,
            record.branch || "unknown",
            record.author || "unknown",
            record.execution_time || "N/A"
          ]
        end
      end
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    def build_header
      title = "📜 Migration History"
      title += " (#{@branch_filter})" if @branch_filter
      title += " (#{@version_filter})" if @version_filter
      title += " (#{@author_filter})" if @author_filter
      title += " (last #{@days_filter} days)" if @days_filter

      Colorizer.info(title)
    end

    def build_table_header
      "Timestamp            Version            Migration                                " \
        "Direction  Status          Branch               Author              "
    end

    def build_separator
      "-" * 140
    end

    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength
    def format_record_row(record)
      timestamp = record.created_at.strftime("%Y-%m-%d %H:%M:%S")
      migration_name = truncate_string(record.migration_file_name || record.version, 40)
      branch_name = truncate_string(record.branch || "unknown", 20)
      author_name = truncate_string(record.author || "unknown", 20)

      # Colorize based on status
      status_colored = case record.status
                       when "applied", "synced"
                         Colorizer.success(record.display_status)
                       when "rolled_back"
                         Colorizer.warning(record.display_status)
                       when "orphaned"
                         Colorizer.error(record.display_status)
                       else
                         record.display_status
                       end

      direction_colored = case record.direction
                          when "UP"
                            Colorizer.success("UP")
                          when "DOWN"
                            Colorizer.warning("DOWN")
                          else
                            record.direction
                          end

      # rubocop:disable Style/FormatStringToken
      format(
        "%-20s %-18s %-40s %-19s %-24s %-20s %-20s",
        timestamp,
        record.version,
        migration_name,
        direction_colored,
        status_colored,
        branch_name,
        author_name
      )
      # rubocop:enable Style/FormatStringToken
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength

    # rubocop:disable Metrics/AbcSize
    def build_summary(records)
      stats = calculate_statistics_for_records(records)

      summary = []
      summary << ""
      summary << Colorizer.info("📊 Summary:")
      summary << "  Total records: #{stats[:total]}"
      summary << "  Applied: #{Colorizer.success(stats[:applied])}"
      summary << "  Rolled back: #{Colorizer.warning(stats[:rolled_back])}"
      summary << "  Orphaned: #{Colorizer.error(stats[:orphaned])}"
      summary << "  Branches: #{stats[:branches].count}"
      summary << "  Date range: #{stats[:date_range]}"

      summary
    end
    # rubocop:enable Metrics/AbcSize

    def build_filters_info
      return [] unless filters_applied?

      info = []
      info << ""
      info << Colorizer.info("🔍 Active Filters:")
      info << "  Branch: #{@branch_filter}" if @branch_filter
      info << "  Version: #{@version_filter}" if @version_filter
      info << "  Author: #{@author_filter}" if @author_filter
      info << "  Days: #{@days_filter}" if @days_filter
      info << "  Limit: #{@limit}" if @limit != DEFAULT_LIMIT

      info
    end

    def no_records_message
      message = "No migration records found"
      message += " for the specified filters" if filters_applied?
      message += ".\n\nTry:"
      message += "\n  - Remove filters to see all records"
      message += "\n  - Run some migrations to generate history"
      message += "\n  - Check that MigrationGuard is properly tracking migrations"

      Colorizer.warning(message)
    end

    def calculate_statistics
      calculate_statistics_for_records(MigrationGuardRecord.all)
    end

    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    def calculate_statistics_for_records(records)
      total = records.count
      applied = records.count { |r| %w[applied synced].include?(r.status) }
      rolled_back = records.count { |r| r.status == "rolled_back" }
      orphaned = records.count { |r| r.status == "orphaned" }
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

    def record_to_hash(record)
      {
        timestamp: record.created_at.iso8601,
        version: record.version,
        migration: record.migration_file_name,
        direction: record.direction,
        status: record.status,
        branch: record.branch,
        author: record.author,
        execution_time: record.execution_time,
        metadata: record.metadata
      }
    end

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

    def truncate_string(string, length)
      return string if string.length <= length

      "#{string[0..(length - 4)]}..."
    end
  end
  # rubocop:enable Metrics/ClassLength
end
