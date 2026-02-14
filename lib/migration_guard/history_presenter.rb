# frozen_string_literal: true

require_relative "colorizer"

module MigrationGuard
  # Formats migration history data for display in table, JSON, and CSV formats
  class HistoryPresenter
    def format_table_output(records, statistics_proc, filters_applied, active_filters)
      return no_records_message(filters_applied) if records.empty?

      build_table(records, statistics_proc, filters_applied, active_filters)
        .flatten.join("\n")
    end

    def format_json_output(records, statistics, active_filters)
      {
        summary: statistics,
        filters: active_filters,
        history: records.map { |record| record_to_hash(record) }
      }.to_json
    end

    # rubocop:disable Metrics/MethodLength
    def format_csv_output(records)
      begin
        require "csv"
      rescue LoadError
        return "CSV format requires the 'csv' gem. Please add it to your Gemfile."
      end

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
    # rubocop:enable Metrics/MethodLength

    private

    def build_table(records, statistics_proc, filters_applied, active_filters)
      output = []
      output << build_header(active_filters)
      output << build_table_header
      output << build_separator
      output << records.map { |record| format_record_row(record) }
      output << build_separator
      output << build_summary(records, statistics_proc)
      output << build_filters_info(active_filters) if filters_applied
      output
    end

    def build_header(active_filters)
      title = "\u{1F4DC} Migration History"
      title += " (#{active_filters[:branch]})" if active_filters[:branch]
      title += " (#{active_filters[:version]})" if active_filters[:version]
      title += " (#{active_filters[:author]})" if active_filters[:author]
      title += " (last #{active_filters[:days]} days)" if active_filters[:days]

      Colorizer.info(title)
    end

    def build_table_header
      "Timestamp            Version            Migration                                " \
        "Direction  Status          Branch               Author              "
    end

    def build_separator
      "-" * 140
    end

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def format_record_row(record)
      timestamp = record.created_at.strftime("%Y-%m-%d %H:%M:%S")
      migration_name = truncate_string(record.migration_file_name || record.version, 40)
      branch_name = truncate_string(record.branch || "unknown", 20)
      author_name = truncate_string(record.author || "unknown", 20)

      status_colored = Colorizer.colorize_status(record.display_status, record.status)
      direction_colored = Colorizer.colorize_direction(record.direction)

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
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    # rubocop:disable Metrics/AbcSize
    def build_summary(records, statistics_proc)
      stats = statistics_proc.call(records)

      summary = []
      summary << ""
      summary << Colorizer.info("\u{1F4CA} Summary:")
      summary << "  Total records: #{stats[:total]}"
      summary << "  Applied: #{Colorizer.success(stats[:applied])}"
      summary << "  Rolled back: #{Colorizer.warning(stats[:rolled_back])}"
      summary << "  Orphaned: #{Colorizer.error(stats[:orphaned])}"
      summary << "  Branches: #{stats[:branches].count}"
      summary << "  Date range: #{stats[:date_range]}"

      summary
    end
    # rubocop:enable Metrics/AbcSize

    def build_filters_info(active_filters)
      labels = { branch: "Branch", version: "Version", author: "Author", days: "Days", limit: "Limit" }
      lines = ["", Colorizer.info("\u{1F50D} Active Filters:")]
      labels.each do |key, label|
        lines << "  #{label}: #{active_filters[key]}" if active_filters[key]
      end
      lines
    end

    def no_records_message(filters_applied)
      message = "No migration records found"
      message += " for the specified filters" if filters_applied
      message += ".\n\nTry:"
      message += "\n  - Remove filters to see all records"
      message += "\n  - Run some migrations to generate history"
      message += "\n  - Check that MigrationGuard is properly tracking migrations"

      Colorizer.warning(message)
    end

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

    def truncate_string(string, length)
      return string if string.length <= length

      "#{string[0..(length - 4)]}..."
    end
  end
end
