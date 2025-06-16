# frozen_string_literal: true

module MigrationGuard
  module Recovery
    # Formats recovery issues for display
    class IssueFormatter
      def self.format(issue, number)
        new.format(issue, number)
      end

      def format(issue, number)
        lines = []
        lines << format_header(issue, number)
        lines << format_version(issue)
        lines << format_description(issue)
        lines << format_severity(issue)
        lines.concat(format_migration_details(issue))
        lines << format_recovery_options(issue)
        lines.join("\n")
      end

      private

      def format_header(issue, number)
        Colorizer.error("#{number}. #{issue[:type].to_s.humanize}")
      end

      def format_version(issue)
        "   Version: #{issue[:version]}"
      end

      def format_description(issue)
        "   #{issue[:description]}"
      end

      def format_severity(issue)
        "   Severity: #{severity_color(issue[:severity])}"
      end

      def format_migration_details(issue)
        return [] unless issue[:migration]

        [
          "   Branch: #{issue[:migration].branch}",
          "   Last updated: #{format_timestamp(issue[:migration].updated_at)}"
        ]
      end

      def format_recovery_options(issue)
        options = issue[:recovery_options].map(&:to_s).join(", ")
        "   Recovery options: #{options}"
      end

      def format_timestamp(time)
        time.strftime("%Y-%m-%d %H:%M:%S")
      end

      def severity_color(severity)
        case severity
        when :critical
          Colorizer.error("CRITICAL")
        when :high
          Colorizer.warning("HIGH")
        when :medium
          Colorizer.info("MEDIUM")
        else
          "LOW"
        end
      end
    end
  end
end
