# frozen_string_literal: true

require "open3"

module MigrationGuard
  module Recovery
    # Handles restore-related recovery actions
    class RestoreAction < BaseAction
      def restore_migration(issue)
        migration = issue[:migration]
        log_info("Restoring migration #{migration.version}...")

        add_to_schema_if_missing(migration.version)
        update_restore_status(migration)
        log_success("✓ Migration restored: #{migration.version}")
        true
      rescue StandardError => e
        log_error("✗ Failed to restore migration: #{e.message}")
        false
      end

      def restore_from_git(issue)
        version = issue[:version]
        log_info("Attempting to restore migration #{version} from git history...")

        commit_hash = find_migration_commit(version)
        return migration_not_found_error unless commit_hash

        file_path = get_migration_file_path(commit_hash, version)
        return file_path_error unless file_path

        restore_file_from_commit(commit_hash, file_path)
        log_success("✓ Migration file restored from commit #{commit_hash}")
        true
      rescue StandardError => e
        log_error("✗ Failed to restore from git: #{e.message}")
        false
      end

      private

      def add_to_schema_if_missing(version)
        return if migration_exists_in_schema?(version)

        ActiveRecord::Base.connection.execute(
          ActiveRecord::Base.sanitize_sql(
            ["INSERT INTO schema_migrations (version) VALUES (?)", version]
          )
        )
      end

      def update_restore_status(migration)
        update_migration_metadata(migration, "restore_migration")
        migration.update!(status: "applied")
      end

      def find_migration_commit(version)
        stdout, _stderr, status = Open3.capture3(
          "git", "log", "--all", "--full-history", "--", "db/migrate/#{version}_*.rb"
        )
        return nil unless status.success? && !stdout.empty?

        match = stdout.lines.first&.match(/commit (\w+)/)
        match&.[](1)
      end

      def get_migration_file_path(commit_hash, version)
        stdout, _stderr, status = Open3.capture3(
          "git", "show", "--name-only", "--pretty=format:", commit_hash
        )
        return nil unless status.success?

        file_path = stdout.lines.find { |line| line.include?("#{version}_") }
        file_path&.strip
      end

      def restore_file_from_commit(commit_hash, file_path) # rubocop:disable Naming/PredicateMethod
        stdout, stderr, status = Open3.capture3(
          "git", "show", "#{commit_hash}:#{file_path}"
        )

        unless status.success?
          log_error("Failed to restore file: #{stderr}")
          return false
        end

        output_path = Rails.root.join(file_path)
        FileUtils.mkdir_p(File.dirname(output_path))
        File.write(output_path, stdout)
        true
      end

      def migration_not_found_error # rubocop:disable Naming/PredicateMethod
        log_error("Migration not found in git history")
        false
      end

      def file_path_error # rubocop:disable Naming/PredicateMethod
        log_error("Could not find migration file in commit")
        false
      end
    end
  end
end
