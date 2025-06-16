# frozen_string_literal: true

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

      def restore_from_git?(issue)
        version = issue[:version]
        log_info("Attempting to restore migration #{version} from git history...")

        commit_hash = find_migration_commit(version)
        return migration_not_found_error? unless commit_hash

        file_path = get_migration_file_path(commit_hash, version)
        return file_path_error? unless file_path

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
        result = `git log --all --full-history -- "db/migrate/#{version}_*.rb" | head -1`
        return nil if result.empty?

        result.match(/commit (\w+)/)[1]
      end

      def get_migration_file_path(commit_hash, version)
        file_list = `git show --name-only --pretty=format: #{commit_hash} | grep "#{version}_"`
        file_path = file_list.strip
        file_path.empty? ? nil : file_path
      end

      def restore_file_from_commit(commit_hash, file_path)
        `git show #{commit_hash}:#{file_path} > #{Rails.root.join(file_path)}`
      end

      def migration_not_found_error?
        log_error("Migration not found in git history")
        false
      end

      def file_path_error?
        log_error("Could not find migration file in commit")
        false
      end
    end
  end
end
