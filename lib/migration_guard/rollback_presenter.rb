# frozen_string_literal: true

require_relative "colorizer"

module MigrationGuard
  # Formats rollback-related output for display
  class RollbackPresenter
    def output_message(message)
      puts message # rubocop:disable Rails/Output
    end

    def display_no_orphaned_migrations
      output_message Colorizer.success("No orphaned migrations found.")
    end

    def display_orphaned_list(orphaned)
      word = Colorizer.pluralize_migration(orphaned.size)
      output_message Colorizer.warning("Found #{orphaned.size} orphaned #{word}:")
      output_message ""
      orphaned.each do |migration|
        output_message "  #{migration.version} - #{migration.branch || 'unknown branch'}"
      end
      output_message ""
    end

    def display_orphaned_list_simple(orphaned)
      word = Colorizer.pluralize_migration(orphaned.size)
      output_message Colorizer.warning("Found #{orphaned.size} orphaned #{word}:")
      orphaned.each do |migration|
        output_message "  #{migration.version}"
      end
      output_message ""
    end

    def display_rollback_progress(version)
      output_message Colorizer.info("Rolling back #{version}...")
    end

    def display_rollback_success(count)
      output_message ""
      word = Colorizer.pluralize_migration(count)
      message = "#{Colorizer.format_checkmark} Successfully rolled back #{count} #{word}"
      output_message Colorizer.success(message)
    end

    def display_specific_rollback_success(version)
      output_message Colorizer.success("#{Colorizer.format_checkmark} Successfully rolled back #{version}")
    end

    def display_already_rolled_back(version)
      output_message Colorizer.warning("Migration #{version} is already rolled back.")
    end

    def display_rollback_error(version, error_message)
      output_message Colorizer.error("Rollback failed for migration #{version}")
      output_message Colorizer.error("   Error: #{error_message}")
    end

    def display_batch_rollback_error(version, error_message)
      output_message Colorizer.error("Failed to roll back #{version}: #{error_message}")
    end

    def display_batch_rollback_results(success_count, failure_count)
      output_message ""
      if failure_count.positive?
        message = "Rolled back #{success_count} migration(s) with #{failure_count} failure(s)"
        output_message Colorizer.warning(message)
      else
        message = "#{Colorizer.format_checkmark} All orphaned migrations rolled back successfully"
        output_message Colorizer.success(message)
      end
    end
  end
end
