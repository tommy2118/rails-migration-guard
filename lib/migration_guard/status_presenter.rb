# frozen_string_literal: true

require_relative "colorizer"

module MigrationGuard
  # Formats migration status data for display
  class StatusPresenter
    def format_status_output(report)
      output = []

      add_header(output, report)
      add_sync_status(output, report)
      add_synced_count(output, report)
      add_orphaned_count(output, report)
      add_missing_count(output, report)
      add_orphaned_section(output, report) if report[:orphaned_count].positive?

      if report[:target_branches]
        add_multi_branch_missing_section(output, report) if report[:missing_by_branch]&.any?
      elsif report[:missing_count].positive?
        add_missing_section(output, report)
      end

      output.join("\n")
    end

    def summary_line(report)
      if report[:orphaned_count].positive?
        count = report[:orphaned_count]
        word = Colorizer.pluralize_migration(count)
        branch = report[:current_branch]
        "MigrationGuard: #{count} orphaned #{word} detected on branch '#{branch}'"
      elsif report[:target_branches]
        format_multi_branch_summary(report)
      elsif report[:missing_count].positive?
        count = report[:missing_count]
        word = Colorizer.pluralize_migration(count)
        "MigrationGuard: #{count} missing #{word} from #{report[:main_branch]}"
      else
        "MigrationGuard: All migrations synced with #{report[:main_branch]}"
      end
    end

    private

    def format_multi_branch_summary(report)
      if report[:missing_by_branch]&.any?
        total_missing = report[:missing_migrations].size
        word = Colorizer.pluralize_migration(total_missing)
        branches = report[:missing_by_branch].keys.join(", ")
        "MigrationGuard: #{total_missing} missing #{word} from branches: #{branches}"
      else
        branches = report[:target_branches].join(", ")
        "MigrationGuard: All migrations synced with branches: #{branches}"
      end
    end

    def format_orphaned_migration(migration)
      lines = ["  #{migration[:version]}"]
      lines << "    Branch: #{migration[:branch]}" if migration[:branch]
      lines << "    Author: #{migration[:author]}" if migration[:author]
      lines << "    Age: #{migration[:age_in_days]} days"
      lines.join("\n")
    end

    def add_header(output, report)
      output << ("\u{2550}" * 55)
      if report[:target_branches]
        branches_text = report[:target_branches].join(", ")
        output << Colorizer.bold("Migration Status (branches: #{branches_text})")
      else
        output << Colorizer.bold("Migration Status (#{report[:main_branch]} branch)")
      end

      output << Colorizer.warning(MigrationGuard::SandboxMessages::START) if MigrationGuard.configuration.sandbox_mode

      output << ("\u{2550}" * 55)
    end

    def add_synced_count(output, report)
      output << Colorizer.format_status_line(
        Colorizer.format_checkmark, "Synced", report[:synced_count], :synced
      )
    end

    def add_orphaned_count(output, report)
      return unless report[:orphaned_count].positive?

      orphaned_line = Colorizer.format_status_line(
        Colorizer.format_warning_symbol, "Orphaned", report[:orphaned_count], :orphaned
      )
      output << "#{orphaned_line} (local only)"
    end

    def add_missing_count(output, report)
      if report[:target_branches]
        return unless report[:missing_by_branch]&.any?

        total_missing = report[:missing_migrations].size
        missing_line = Colorizer.format_status_line(
          Colorizer.format_error_symbol, "Missing", total_missing, :missing
        )
        output << "#{missing_line} (in target branches, not local)"
      else
        return unless report[:missing_count].positive?

        missing_line = Colorizer.format_status_line(
          Colorizer.format_error_symbol, "Missing", report[:missing_count], :missing
        )
        output << "#{missing_line} (in trunk, not local)"
      end
    end

    # rubocop:disable Metrics/AbcSize
    def add_sync_status(output, report)
      if report[:target_branches]
        return unless report[:orphaned_count].zero? && report[:missing_by_branch]&.empty?

        branches = report[:target_branches].join(", ")
        output << Colorizer.format_status_line(
          Colorizer.format_checkmark, "All migrations synced with #{branches}",
          report[:synced_count], :synced
        )
      else
        return unless report[:orphaned_count].zero? && report[:missing_count].zero?

        output << Colorizer.format_status_line(
          Colorizer.format_checkmark, "All migrations synced with #{report[:main_branch]}",
          report[:synced_count], :synced
        )
      end
    end
    # rubocop:enable Metrics/AbcSize

    def add_orphaned_section(output, report)
      output << ""
      output << Colorizer.warning("Orphaned Migrations:")
      report[:orphaned_migrations].each { |m| output << format_orphaned_migration(m) }
      output << ""
      output << Colorizer.info("Run `rails db:migration:rollback_orphaned` to clean up")
    end

    def add_missing_section(output, report)
      output << ""
      output << Colorizer.error("Missing Migrations:")
      report[:missing_migrations].each { |version| output << "  #{version}" }
      output << ""
      output << Colorizer.info("Run `rails db:migrate` to apply missing migrations")
    end

    def add_multi_branch_missing_section(output, report)
      output << ""
      output << Colorizer.error("Missing Migrations by Branch:")
      report[:missing_by_branch].each do |branch, versions|
        output << ""
        output << "  #{Colorizer.bold(branch)}:"
        versions.each { |version| output << "    #{version}" }
      end
      output << ""
      output << Colorizer.info("Run `rails db:migrate` to apply missing migrations")
    end
  end
end
